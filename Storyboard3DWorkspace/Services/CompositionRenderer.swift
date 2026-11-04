//
//  CompositionRenderer.swift
//  Storyboard3DWorkspace
//

import CoreGraphics
import Metal
import RealityKit

/// Renders the staged composition (base, objects, and backdrop) to a flat image, offscreen,
/// the way a Blender camera renders a scene.
///
/// visionOS apps can't read the passthrough camera feed or screenshot their own immersive
/// space, so capture builds a separate `RealityRenderer` scene: a copy of the base and its
/// objects at their current poses, a copy of the backdrop exactly where the viewer sees
/// it, studio lighting, and a camera placed at the viewer's head. Passthrough and app
/// windows can't appear in the output because they never enter that scene.
final class CompositionRenderer {
    enum RenderError: LocalizedError {
        case metalUnavailable
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .metalUnavailable: "This device can't render captures."
            case .renderFailed: "The capture couldn't be rendered."
            }
        }
    }

    static let outputWidth = 2560
    static let outputHeight = 1440

    /// - Parameters:
    ///   - scene: The base with its objects. Rendered at its current world pose.
    ///   - backdrop: The live backdrop plane, copied at its current world pose.
    ///   - background: The backdrop image, used if a frame-filling backdrop must be built instead.
    ///   - camera: Where to render from.
    func render(scene: Entity, backdrop: ModelEntity, background: CGImage,
                camera captureCamera: CaptureCamera) async throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.metalUnavailable }

        let renderer = try RealityRenderer()

        // A copy of the staged scene, minus interaction-only pieces.
        let subject = scene.clone(recursive: true)
        subject.findEntity(named: WorkspaceScene.selectionIndicatorName)?.removeFromParent()
        Self.stripInteraction(from: subject)
        subject.transform = Transform(matrix: scene.transformMatrix(relativeTo: nil))

        let bounds = subject.visualBounds(relativeTo: nil)
        let center = bounds.isEmpty ? subject.position : bounds.center
        let radius = max(bounds.isEmpty ? 0.3 : simd_length(bounds.extents) / 2, 0.05)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = captureCamera.lens.verticalFOV * 180 / .pi
        camera.camera.near = 0.01
        camera.camera.far = 100
        camera.position = captureCamera.position
        camera.orientation = captureCamera.orientation

        let backdropCopy = try await makeBackdrop(
            live: backdrop,
            image: background,
            camera: captureCamera,
            sceneCenter: center,
            sceneRadius: radius
        )

        renderer.entities.append(contentsOf: [subject, backdropCopy, camera] + Self.studioLights(camera: captureCamera, center: center))
        renderer.activeCamera = camera
        renderer.lighting.resource = try await EnvironmentResource(equirectangular: Self.makeStudioEnvironment())
        renderer.lighting.intensityExponent = 0.4
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.antialiasing = .multisample4X

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Self.outputWidth,
            height: Self.outputHeight,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.renderFailed }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try renderer.update(0)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in
                    continuation.resume()
                })
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return try Self.makeImage(from: texture)
    }

    private static func stripInteraction(from entity: Entity) {
        entity.components.remove(ManipulationComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(HoverEffectComponent.self)
        entity.components.remove(CollisionComponent.self)
        for child in entity.children {
            stripInteraction(from: child)
        }
    }

    // MARK: Backdrop

    /// Copies the live backdrop so the image sits exactly where the viewer sees it. If its
    /// edges would show inside the frame, it's enlarged around the point the camera looks
    /// at, keeping that part of the image in place. If the camera doesn't face the backdrop
    /// at all, a frame-filling plane is built behind the scene instead.
    private func makeBackdrop(live: ModelEntity, image: CGImage, camera: CaptureCamera,
                              sceneCenter: SIMD3<Float>, sceneRadius: Float) async throws -> Entity {
        if live.isEnabled, let mesh = live.model?.mesh {
            let copy = live.clone(recursive: false)
            // The copy must hold still: the live system would otherwise re-aim it in the render scene.
            copy.components.remove(ViewerFacingBackdropComponent.self)
            copy.transform = Transform(matrix: live.transformMatrix(relativeTo: nil))
            let halfSize = SIMD2(mesh.bounds.extents.x, mesh.bounds.extents.y) / 2

            if let scale = Self.coverageScale(planeTransform: copy.transformMatrix(relativeTo: nil),
                                              halfSize: halfSize, camera: camera) {
                if scale > 1 {
                    // Grow around the point on the plane where the camera's center ray lands.
                    let axisHit = Self.hit(direction: camera.orientation.act([0, 0, -1]), from: camera.position,
                                           planeTransform: copy.transformMatrix(relativeTo: nil))!
                    let world = copy.transformMatrix(relativeTo: nil)
                    let hitWorld = world * SIMD4(axisHit.x, axisHit.y, 0, 1)
                    let newCenter = SIMD3(hitWorld.x, hitWorld.y, hitWorld.z)
                        + (copy.position - SIMD3(hitWorld.x, hitWorld.y, hitWorld.z)) * scale
                    copy.scale = SIMD3(repeating: scale)
                    copy.position = newCenter
                }
                return copy
            }
        }

        // Fallback: a plane perpendicular to the camera, behind the scene, filling the frame.
        let texture = try await TextureResource(image: image, withName: nil, options: .init(semantic: .color))
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(texture: .init(texture))

        let forward = camera.orientation.act([0, 0, -1])
        let depth = max(simd_dot(sceneCenter - camera.position, forward), 0.2) + sceneRadius + BackdropLayout.gapBehindTarget
        let frameHeight = 2 * depth * tan(camera.lens.verticalFOV / 2) * 1.02
        let frameWidth = frameHeight * CaptureLens.aspect
        let imageAspect = Float(image.width) / Float(max(image.height, 1))
        let size: SIMD2<Float> = imageAspect > CaptureLens.aspect
            ? [frameHeight * imageAspect, frameHeight]
            : [frameWidth, frameWidth / imageAspect]

        let plane = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y), materials: [material])
        plane.position = camera.position + forward * depth
        plane.orientation = camera.orientation
        return plane
    }

    /// How much the plane must grow (about the camera's center-ray hit point) to fill
    /// the frame. Nil when a frame corner ray misses the plane.
    private static func coverageScale(planeTransform: simd_float4x4, halfSize: SIMD2<Float>,
                                      camera: CaptureCamera) -> Float? {
        guard let center = hit(direction: camera.orientation.act([0, 0, -1]), from: camera.position,
                               planeTransform: planeTransform),
              abs(center.x) < halfSize.x, abs(center.y) < halfSize.y
        else { return nil }

        let tanV = tan(camera.lens.verticalFOV / 2)
        let tanH = tanV * CaptureLens.aspect
        var scale: Float = 1
        for corner: SIMD2<Float> in [[-1, -1], [1, -1], [1, 1], [-1, 1]] {
            let local = simd_normalize(SIMD3(corner.x * tanH, corner.y * tanV, -1))
            guard let point = hit(direction: camera.orientation.act(local), from: camera.position,
                                  planeTransform: planeTransform)
            else { return nil }
            for axis in 0..<2 {
                let offset = point[axis] - center[axis]
                let room = offset > 0 ? halfSize[axis] - center[axis] : halfSize[axis] + center[axis]
                scale = max(scale, abs(offset) / room * 1.02)
            }
        }
        return scale
    }

    /// Where a ray meets the plane, in the plane's local 2D coordinates. Nil if it misses
    /// or the plane is behind the camera.
    private static func hit(direction: SIMD3<Float>, from origin: SIMD3<Float>,
                            planeTransform: simd_float4x4) -> SIMD2<Float>? {
        let normal = simd_normalize(SIMD3(planeTransform.columns.2.x, planeTransform.columns.2.y, planeTransform.columns.2.z))
        let planePoint = SIMD3(planeTransform.columns.3.x, planeTransform.columns.3.y, planeTransform.columns.3.z)
        let denominator = simd_dot(direction, normal)
        guard abs(denominator) > 1e-4 else { return nil }
        let distance = simd_dot(planePoint - origin, normal) / denominator
        guard distance > 0 else { return nil }
        let world = origin + direction * distance
        let local = planeTransform.inverse * SIMD4(world, 1)
        return SIMD2(local.x, local.y)
    }

    // MARK: Lighting

    /// Classic three-point lighting placed relative to the camera: a shadow-casting key
    /// light above and to the left, a soft fill from the right, and a rim light from
    /// behind that separates the scene from the backdrop.
    private static func studioLights(camera: CaptureCamera, center: SIMD3<Float>) -> [Entity] {
        let right = camera.orientation.act([1, 0, 0])
        var back = center - camera.position
        back.y = 0
        back = simd_length(back) > 1e-3 ? simd_normalize(back) : [0, 0, -1]
        let up = SIMD3<Float>(0, 1, 0)

        func light(intensity: Float, from offset: SIMD3<Float>, shadows: Bool) -> DirectionalLight {
            let light = DirectionalLight()
            light.light.intensity = intensity
            if shadows { light.shadow = DirectionalLightComponent.Shadow() }
            // A directional light shines down its -Z axis.
            light.orientation = .upright(facing: offset)
            return light
        }

        return [
            light(intensity: 2600, from: -back * 0.8 - right * 0.9 + up * 1.6, shadows: true),
            light(intensity: 800, from: -back * 1.0 + right * 1.0 + up * 0.4, shadows: false),
            light(intensity: 1400, from: back * 1.0 + up * 1.2, shadows: false)
        ]
    }

    /// A soft studio gradient used as image-based lighting for the scene.
    private static func makeStudioEnvironment() -> CGImage {
        let width = 512
        let height = 256
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let colors = [
            CGColor(srgbRed: 0.96, green: 0.97, blue: 1.00, alpha: 1),
            CGColor(srgbRed: 0.80, green: 0.82, blue: 0.85, alpha: 1),
            CGColor(srgbRed: 0.42, green: 0.42, blue: 0.43, alpha: 1)
        ] as CFArray
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.5, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        return context.makeImage()!
    }

    private static func makeImage(from texture: any MTLTexture) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                         | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw RenderError.renderFailed }
        return image
    }
}
