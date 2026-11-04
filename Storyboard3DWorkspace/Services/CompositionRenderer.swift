//
//  CompositionRenderer.swift
//  Storyboard3DWorkspace
//

import CoreGraphics
import Metal
import RealityKit

/// Renders the staged composition (model plus backdrop) to a flat image, offscreen.
///
/// visionOS apps can't read the passthrough camera feed or screenshot their own
/// immersive space, so capture uses a separate `RealityRenderer` scene instead: a copy
/// of the model at its current pose, seen from the viewer's head position, against a
/// backdrop plane sized to fill the frame. Passthrough and app windows can't appear
/// in the output because they never enter that scene.
///
/// The viewpoint matches where the viewer is standing. The lens is chosen to frame the
/// model, so the result reads like a product shot rather than a wide-angle view.
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

    /// Gap between the model and the backdrop, matching the live scene.
    private static let backdropGap: Float = 0.9

    func render(model: Entity, background: CGImage, viewerPosition: SIMD3<Float>) async throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.metalUnavailable }

        let renderer = try RealityRenderer()
        let aspect = Float(Self.outputWidth) / Float(Self.outputHeight)

        // Copy of the model at its current world pose, minus interaction-only pieces.
        let subject = model.clone(recursive: true)
        subject.components.remove(ManipulationComponent.self)
        subject.components.remove(InputTargetComponent.self)
        subject.components.remove(HoverEffectComponent.self)
        subject.components.remove(CollisionComponent.self)
        subject.findEntity(named: WorkspaceScene.selectionIndicatorName)?.removeFromParent()
        subject.transform = Transform(matrix: model.transformMatrix(relativeTo: nil))

        let bounds = subject.visualBounds(relativeTo: nil)
        let center = bounds.isEmpty ? subject.position : bounds.center
        let radius = max(bounds.isEmpty ? 0.3 : length(bounds.extents) / 2, 0.05)

        var toViewer = viewerPosition - center
        if length(toViewer) < radius * 1.5 {
            toViewer = normalize(length(toViewer) > 1e-4 ? toViewer : [0, 0, 1]) * radius * 3
        }
        let distance = length(toViewer)
        let cameraPosition = center + toViewer
        let cameraOrientation = simd_quatf.upright(facing: toViewer)

        // Vertical field of view that frames the model with a comfortable margin.
        // `radius` is a bounding sphere, which overstates flat models, hence the < 1 factor.
        let halfFOV = min(max(atan(radius * 0.85 / distance), 0.09), 0.6)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = halfFOV * 2 * 180 / .pi
        camera.camera.near = 0.01
        camera.camera.far = 100
        camera.position = cameraPosition
        camera.orientation = cameraOrientation

        let backdrop = try await makeBackdrop(
            image: background,
            distanceFromCamera: distance + radius + Self.backdropGap,
            halfFOV: halfFOV,
            frameAspect: aspect,
            cameraPosition: cameraPosition,
            cameraOrientation: cameraOrientation
        )

        let keyLight = DirectionalLight()
        keyLight.light.intensity = 2600
        keyLight.shadow = DirectionalLightComponent.Shadow()
        // Above, behind, and to the left of the camera, aimed at the model.
        let right = cameraOrientation.act([1, 0, 0])
        let lightPosition = center + normalize(toViewer) * 1.0 - right * 0.8 + [0, 1.6, 0]
        keyLight.orientation = simd_quatf.upright(facing: lightPosition - center)

        renderer.entities.append(contentsOf: [subject, backdrop, keyLight, camera])
        renderer.activeCamera = camera
        renderer.lighting.resource = try await EnvironmentResource(equirectangular: Self.makeStudioEnvironment())
        renderer.lighting.intensityExponent = 0.6
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

    /// An unlit plane perpendicular to the camera that aspect-fills the frame.
    private func makeBackdrop(image: CGImage, distanceFromCamera: Float, halfFOV: Float, frameAspect: Float,
                              cameraPosition: SIMD3<Float>, cameraOrientation: simd_quatf) async throws -> Entity {
        let texture = try await TextureResource(image: image, withName: nil, options: .init(semantic: .color))
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(texture: .init(texture))

        let frameHeight = 2 * distanceFromCamera * tan(halfFOV)
        let frameWidth = frameHeight * frameAspect
        let imageAspect = Float(image.width) / Float(max(image.height, 1))
        let planeSize: SIMD2<Float> = imageAspect > frameAspect
            ? [frameHeight * imageAspect, frameHeight]
            : [frameWidth, frameWidth / imageAspect]

        // Slightly oversized so no edge can show at the frame border.
        let plane = ModelEntity(mesh: .generatePlane(width: planeSize.x * 1.02, height: planeSize.y * 1.02),
                                materials: [material])
        plane.position = cameraPosition + cameraOrientation.act([0, 0, -distanceFromCamera])
        plane.orientation = cameraOrientation
        return plane
    }

    /// A soft studio gradient used as image-based lighting for the model.
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
