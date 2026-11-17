//
//  CompositionRenderer.swift
//  Storyboard3DWorkspace
//

import Accelerate
import CoreGraphics
import CoreImage
import Metal
import RealityKit
#if canImport(UIKit)
import UIKit
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformColor = NSColor
#endif

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
    /// The quick preview in the camera settings.
    static let previewWidth = 640
    static let previewHeight = 360

    /// - Parameters:
    ///   - scene: The base with its objects. Rendered at its current world pose.
    ///   - backdrop: The live backdrop plane, copied at its current world pose.
    ///   - background: The backdrop image, used if a frame-filling backdrop must be built instead.
    ///   - camera: Where to render from.
    ///   - lighting: The lighting mood.
    ///   - look: Frame format and film grade applied after rendering.
    func render(scene: Entity, backdrop: ModelEntity, background: CGImage,
                camera captureCamera: CaptureCamera, lighting: LightingPreset = .studio,
                look: CaptureLook = .plain) async throws -> CGImage {
        try await render(snapshot: Self.snapshot(of: scene), backdrop: backdrop, backdropPose: nil,
                         background: background, camera: captureCamera, lighting: lighting, look: look)
    }

    /// A render-ready copy of the staged scene at its current world pose, minus
    /// interaction-only pieces. Taking it is instant, so the live scene can be posed,
    /// copied, and put back before anything is drawn.
    static func snapshot(of scene: Entity) -> Entity {
        // Heads that follow a target, and held objects that follow hands, update every frame;
        // make sure they're in place for this pose (heads first, since hands don't depend on them).
        LookTracking.aimAll(in: scene)
        HeldProps.attachAll(in: scene)
        let subject = scene.clone(recursive: true)
        subject.findEntity(named: WorkspaceScene.selectionIndicatorName)?.removeFromParent()
        subject.findEntity(named: WorkspaceScene.onionSkinName)?.removeFromParent()
        stripInteraction(from: subject)
        subject.transform = Transform(matrix: scene.transformMatrix(relativeTo: nil))
        return subject
    }

    /// - Parameters:
    ///   - snapshot: From `snapshot(of:)`. Not modified, so it can be rendered again.
    ///   - backdropPose: Where to put the backdrop; nil uses the live backdrop's position.
    ///   - width: Output width in pixels; the preview uses a smaller size.
    ///   - height: Output height in pixels.
    func render(snapshot: Entity, backdrop: ModelEntity, backdropPose: Transform?, background: CGImage,
                camera captureCamera: CaptureCamera, lighting: LightingPreset,
                look: CaptureLook = .plain, width: Int? = nil, height: Int? = nil) async throws -> CGImage {
        let width = width ?? Self.outputWidth
        let height = height ?? Self.outputHeight
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.metalUnavailable }

        let renderer = try RealityRenderer()
        let subject = snapshot.clone(recursive: true)

        let bounds = subject.visualBounds(relativeTo: nil)
        let center = bounds.isEmpty ? subject.position : bounds.center
        let radius = max(bounds.isEmpty ? 0.3 : simd_length(bounds.extents) / 2, 0.05)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = captureCamera.lens.verticalFOV * 180 / .pi
        camera.camera.near = 0.01
        camera.camera.far = 100
        camera.position = captureCamera.position
        camera.orientation = captureCamera.orientation

        // With lens blur, the camera also renders from points across the lens, each turned
        // slightly toward the focus point, so the backdrop needs room beyond the frame.
        let lensPlan = look.depthOfField.map { LensPlan($0, subject: subject, camera: captureCamera,
                                                        verticalFOV: captureCamera.lens.verticalFOV) }

        let backdropCopy = try await makeBackdrop(
            live: backdrop,
            image: background,
            pose: backdropPose,
            camera: captureCamera,
            sceneCenter: center,
            sceneRadius: radius,
            tint: lighting.backdropTint,
            margin: lensPlan?.backdropMargin ?? 0
        )

        renderer.entities.append(contentsOf: [subject, backdropCopy, camera]
                                 + Self.lights(for: lighting, camera: captureCamera, center: center))
        renderer.activeCamera = camera
        renderer.lighting.resource = try await EnvironmentResource(equirectangular: Self.makeEnvironment(for: lighting))
        renderer.lighting.intensityExponent = lighting.environmentExposure
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.antialiasing = .multisample4X

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.renderFailed }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        func renderFrame() async throws {
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
        }

        let image: CGImage
        if var lensPlan {
            lensPlan.backdropDepth = Self.depth(of: backdropCopy, from: captureCamera)
            var accumulator = Accumulator(width: width, height: height)
            image = try await Self.renderThroughLens(lensPlan, camera: camera, captureCamera: captureCamera,
                                                     texture: texture, accumulator: &accumulator, render: renderFrame)
        } else {
            try await renderFrame()
            image = try Self.makeImage(from: texture)
        }
        return FilmFinisher.finish(image, look: look, lighting: lighting)
    }

    // MARK: Depth of field

    /// What a lens-blur render needs to know about the shot.
    struct LensPlan {
        let depthOfField: DepthOfField
        let focusDistance: Float
        let apertureRadius: Float
        let verticalFOV: Float
        /// The nearest and farthest the scene's objects reach in front of the camera.
        let nearest: Float
        let farthest: Float
        /// How far the backdrop is, once it's placed.
        var backdropDepth: Float?
        /// At most this many renders, for the animatic.
        var sampleLimit: Int?

        init(_ depthOfField: DepthOfField, subject: Entity, camera: CaptureCamera, verticalFOV: Float, sampleLimit: Int? = nil) {
            self.depthOfField = depthOfField
            self.verticalFOV = verticalFOV
            self.sampleLimit = sampleLimit
            focusDistance = CompositionRenderer.focusDistance(for: depthOfField, in: subject, camera: camera)
            apertureRadius = depthOfField.apertureRadius(for: camera.lens)
            let bounds = subject.visualBounds(relativeTo: nil)
            let forward = camera.orientation.act([0, 0, -1])
            var near = Float.infinity, far: Float = 0
            if !bounds.isEmpty {
                for corner in 0..<8 {
                    let point = SIMD3(corner & 1 == 0 ? bounds.min.x : bounds.max.x, corner & 2 == 0 ? bounds.min.y : bounds.max.y,
                                      corner & 4 == 0 ? bounds.min.z : bounds.max.z)
                    let depth = simd_dot(point - camera.position, forward)
                    near = min(near, depth)
                    far = max(far, depth)
                }
            }
            nearest = max(near.isFinite ? near : focusDistance, 0.05)
            farthest = max(far, focusDistance)
        }

        /// Extra room the backdrop needs beyond the frame, since renders from the edge of the
        /// lens turn slightly toward the focus point.
        var backdropMargin: Float { 2 * apertureRadius * (1 / focusDistance + 1) / tan(verticalFOV / 2) }

        var sampleCount: Int {
            let count = CompositionRenderer.sampleCount(for: depthOfField)
            return sampleLimit.map { min($0, count) } ?? count
        }

        /// The widest blur in the picture, in pixels for a frame `height` pixels tall.
        func largestBlur(height: Int) -> Float {
            let pixelsPerRadian = Float(height) / verticalFOV
            let depths = [nearest, farthest, backdropDepth ?? farthest].filter { $0 > 0.01 }
            let widest = depths.map { abs(1 / focusDistance - 1 / $0) }.max() ?? 0
            return 2 * apertureRadius * widest * pixelsPerRadian
        }
    }

    /// A real lens blurs because light reaches the sensor through every point of its opening.
    /// Renders from points spread across that opening, each aimed at the same focus point, and
    /// averages them: what's at the focus distance lines up in every render and stays sharp,
    /// and everything else smears by how far it is from it. With few renders a strong blur
    /// shows as separate copies, so where the renders disagree a lot (only out of focus), the
    /// average is softened just enough to merge them.
    static func renderThroughLens(_ plan: LensPlan, camera: PerspectiveCamera, captureCamera: CaptureCamera,
                                  texture: any MTLTexture, accumulator: inout Accumulator,
                                  render: () async throws -> Void) async throws -> CGImage {
        let views = apertureViews(of: captureCamera, focusDistance: plan.focusDistance, radius: plan.apertureRadius,
                                  count: plan.sampleCount)
        accumulator.reset()
        for view in views {
            camera.position = view.position
            camera.orientation = view.orientation
            try await render()
            accumulator.add(texture)
        }
        camera.position = captureCamera.position
        camera.orientation = captureCamera.orientation
        let spacing = plan.largestBlur(height: accumulator.height) / Float(views.count).squareRoot()
        return try accumulator.finish(smoothing: spacing * 0.6)
    }

    /// How far an entity is in front of the camera.
    static func depth(of entity: Entity, from camera: CaptureCamera) -> Float {
        simd_dot(entity.position(relativeTo: nil) - camera.position, camera.orientation.act([0, 0, -1]))
    }

    /// Renders to average for lens blur. Wide apertures blur more, so they need more
    /// renders to keep the blur smooth instead of showing separate copies.
    static func sampleCount(for depthOfField: DepthOfField) -> Int {
        switch depthOfField.fStop {
        case ..<2.5: 48
        case ..<5: 32
        default: 16
        }
    }

    /// How far in front of the camera to focus: on the chosen object's center, or, for
    /// automatic focus, on the nearest object the frame's center passes through. If the
    /// center hits nothing, the object nearest the center of the frame is used.
    static func focusDistance(for depthOfField: DepthOfField, in scene: Entity, camera: CaptureCamera) -> Float {
        let forward = camera.orientation.act([0, 0, -1])
        func depth(of point: SIMD3<Float>) -> Float { simd_dot(point - camera.position, forward) }

        var objects: [(id: ObjectID, bounds: BoundingBox)] = []
        func collect(_ entity: Entity) {
            if let placed = entity.components[PlacedObjectComponent.self] {
                if entity.isEnabled {
                    let bounds = entity.visualBounds(relativeTo: nil)
                    if !bounds.isEmpty { objects.append((placed.id, bounds)) }
                }
                return
            }
            entity.children.forEach(collect)
        }
        collect(scene)

        if let id = depthOfField.focusObject, let chosen = objects.first(where: { $0.id == id }) {
            return max(depth(of: chosen.bounds.center), 0.05)
        }
        let hits = objects.compactMap { object in
            rayEntry(origin: camera.position, direction: forward, bounds: object.bounds).map { _ in depth(of: object.bounds.center) }
        }
        if let nearest = hits.filter({ $0 > 0 }).min() { return max(nearest, 0.05) }

        // Nothing at the center: focus on the object closest to the middle of the picture.
        let inFront = objects.filter { depth(of: $0.bounds.center) > 0.05 }
        let closest = inFront.min { a, b in
            angle(to: a.bounds.center, from: camera.position, forward: forward)
                < angle(to: b.bounds.center, from: camera.position, forward: forward)
        }
        if let closest { return depth(of: closest.bounds.center) }
        let bounds = scene.visualBounds(relativeTo: nil)
        return bounds.isEmpty ? 0.5 : max(depth(of: bounds.center), 0.05)
    }

    private static func angle(to point: SIMD3<Float>, from origin: SIMD3<Float>, forward: SIMD3<Float>) -> Float {
        acos(min(max(simd_dot(simd_normalize(point - origin), forward), -1), 1))
    }

    /// Where a ray enters a box, as a distance along the ray; nil if it misses.
    static func rayEntry(origin: SIMD3<Float>, direction: SIMD3<Float>, bounds: BoundingBox) -> Float? {
        var near = -Float.infinity
        var far = Float.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 1e-6 {
                if origin[axis] < bounds.min[axis] || origin[axis] > bounds.max[axis] { return nil }
                continue
            }
            let a = (bounds.min[axis] - origin[axis]) / direction[axis]
            let b = (bounds.max[axis] - origin[axis]) / direction[axis]
            near = max(near, min(a, b))
            far = min(far, max(a, b))
        }
        guard near <= far, far > 0 else { return nil }
        return max(near, 0)
    }

    /// Camera poses spread evenly across a round lens opening (a sunflower spiral), each
    /// turned to look at the same point at `focusDistance` straight ahead of the original.
    static func apertureViews(of camera: CaptureCamera, focusDistance: Float, radius: Float,
                              count: Int) -> [(position: SIMD3<Float>, orientation: simd_quatf)] {
        let right = camera.orientation.act([1, 0, 0])
        let up = camera.orientation.act([0, 1, 0])
        let focus = camera.position + camera.orientation.act([0, 0, -1]) * focusDistance
        let goldenAngle = Float.pi * (3 - sqrt(5))
        return (0..<count).map { index in
            let r = radius * sqrt((Float(index) + 0.5) / Float(count))
            let theta = Float(index) * goldenAngle
            let position = camera.position + right * (r * cos(theta)) + up * (r * sin(theta))
            return (position, lookRotation(forward: simd_normalize(focus - position), up: up))
        }
    }

    /// A rotation whose -Z points along `forward`, keeping +Y as close to `up` as it can.
    private static func lookRotation(forward: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf {
        let back = -forward
        let right = simd_normalize(simd_cross(up, back))
        let trueUp = simd_cross(back, right)
        return simd_quatf(simd_float3x3(columns: (right, trueUp, back)))
    }

    /// Sums rendered frames, pixel by pixel, to average them, and tracks how much each
    /// pixel's brightness varies between them.
    struct Accumulator {
        let width: Int
        let height: Int
        private var sums: [Float]
        private var frame: [Float]
        private var bytes: [UInt8]
        private var luma: [Float]
        private var lumaSums: [Float]
        private var lumaSquares: [Float]
        private var count = 0

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            sums = [Float](repeating: 0, count: width * height * 4)
            frame = sums
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            luma = [Float](repeating: 0, count: width * height)
            lumaSums = luma
            lumaSquares = luma
        }

        mutating func reset() {
            vDSP_vclr(&sums, 1, vDSP_Length(sums.count))
            vDSP_vclr(&lumaSums, 1, vDSP_Length(lumaSums.count))
            vDSP_vclr(&lumaSquares, 1, vDSP_Length(lumaSquares.count))
            count = 0
        }

        mutating func add(_ texture: any MTLTexture) {
            texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let length = vDSP_Length(bytes.count)
            vDSP_vfltu8(bytes, 1, &frame, 1, length)
            vDSP_vadd(sums, 1, frame, 1, &sums, 1, length)

            // Brightness of each pixel (stored as BGRA), and its square, for the spread.
            let pixels = vDSP_Length(width * height)
            frame.withUnsafeBufferPointer { channels in
                guard let base = channels.baseAddress else { return }
                var blue: Float = 0.114, green: Float = 0.587, red: Float = 0.299
                vDSP_vsmul(base, 4, &blue, &luma, 1, pixels)
                vDSP_vsma(base + 1, 4, &green, luma, 1, &luma, 1, pixels)
                vDSP_vsma(base + 2, 4, &red, luma, 1, &luma, 1, pixels)
            }
            vDSP_vadd(lumaSums, 1, luma, 1, &lumaSums, 1, pixels)
            vDSP_vsq(luma, 1, &luma, 1, pixels)
            vDSP_vadd(lumaSquares, 1, luma, 1, &lumaSquares, 1, pixels)
            count += 1
        }

        /// The average, in the same pixel layout as `makeImage(from:)`. Frames are averaged as
        /// stored (sRGB-encoded), which is close enough to how lens blur mixes light here.
        /// - Parameter smoothing: Blur radius (pixels) for areas where the frames disagree a lot.
        mutating func finish(smoothing: Float) throws -> CGImage {
            var divisor = Float(max(count, 1))
            let length = vDSP_Length(sums.count)
            vDSP_vsdiv(sums, 1, &divisor, &frame, 1, length)
            vDSP_vfixru8(frame, 1, &bytes, 1, length)
            let average = try CompositionRenderer.makeImage(bytes: bytes, width: width, height: height)
            guard smoothing >= 1, count > 1 else { return average }

            // Spread of brightness: sqrt(mean of squares − square of mean), 0–255.
            let pixels = vDSP_Length(width * height)
            var mean = [Float](repeating: 0, count: width * height)
            vDSP_vsdiv(lumaSums, 1, &divisor, &mean, 1, pixels)
            vDSP_vsq(mean, 1, &mean, 1, pixels)
            vDSP_vsdiv(lumaSquares, 1, &divisor, &luma, 1, pixels)
            vDSP_vsub(mean, 1, luma, 1, &luma, 1, pixels)
            var zero: Float = 0, ceiling: Float = 1e9
            vDSP_vclip(luma, 1, &zero, &ceiling, &luma, 1, pixels)
            vvsqrtf(&luma, luma, [Int32(width * height)])
            // Little spread (in focus) keeps the average; lots (copies of a far blur) takes the softened one.
            var offset: Float = -3, scale: Float = 255 / 12
            vDSP_vsadd(luma, 1, &offset, &luma, 1, pixels)
            vDSP_vsmul(luma, 1, &scale, &luma, 1, pixels)
            var top: Float = 255
            vDSP_vclip(luma, 1, &zero, &top, &luma, 1, pixels)
            var maskBytes = [UInt8](repeating: 0, count: width * height)
            vDSP_vfixru8(luma, 1, &maskBytes, 1, pixels)
            guard let provider = CGDataProvider(data: Data(maskBytes) as CFData),
                  let maskImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            else { return average }

            let source = CIImage(cgImage: average)
            let extent = source.extent
            let softened = source.clampedToExtent().applyingGaussianBlur(sigma: Double(smoothing)).cropped(to: extent)
            // Widen the mask a little so the edges of blurred areas soften too.
            let mask = CIImage(cgImage: maskImage).clampedToExtent()
                .applyingGaussianBlur(sigma: Double(smoothing) * 0.5).cropped(to: extent)
            let blended = softened.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: source, kCIInputMaskImageKey: mask,
            ])
            return CompositionRenderer.ciContext.createCGImage(blended, from: extent, format: .RGBA8,
                                                               colorSpace: average.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
                ?? average
        }
    }

    fileprivate static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func stripInteraction(from entity: Entity) {
        entity.components.remove(ManipulationComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(HoverEffectComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(ImageBasedLightReceiverComponent.self)
        for child in entity.children {
            stripInteraction(from: child)
        }
    }

    // MARK: Backdrop

    /// Copies the live backdrop so the image sits exactly where the viewer sees it. If its
    /// edges would show inside the frame, it's enlarged around the point the camera looks
    /// at, keeping that part of the image in place. If the camera doesn't face the backdrop
    /// at all, a frame-filling plane is built behind the scene instead.
    private func makeBackdrop(live: ModelEntity, image: CGImage, pose: Transform?, camera: CaptureCamera,
                              sceneCenter: SIMD3<Float>, sceneRadius: Float, tint: SIMD3<Float>,
                              texture cachedTexture: TextureResource? = nil, margin: Float = 0) async throws -> Entity {
        if live.isEnabled, let mesh = live.model?.mesh {
            let copy = live.clone(recursive: false)
            // The copy must hold still: the live system would otherwise re-aim it in the render scene.
            copy.components.remove(ViewerFacingBackdropComponent.self)
            copy.transform = pose ?? Transform(matrix: live.transformMatrix(relativeTo: nil))
            if var material = copy.model?.materials.first as? UnlitMaterial {
                material.color.tint = Self.color(tint)
                copy.model?.materials = [material]
            }
            let halfSize = SIMD2(mesh.bounds.extents.x, mesh.bounds.extents.y) / 2

            if let fitScale = Self.coverageScale(planeTransform: copy.transformMatrix(relativeTo: nil),
                                                 halfSize: halfSize, camera: camera) {
                let scale = margin > 0 ? fitScale * (1 + margin) : fitScale
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
        let texture: TextureResource
        if let cachedTexture {
            texture = cachedTexture
        } else {
            texture = try await TextureResource(image: image, withName: nil, options: .init(semantic: .color))
        }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: Self.color(tint), texture: .init(texture))

        let forward = camera.orientation.act([0, 0, -1])
        let depth = max(simd_dot(sceneCenter - camera.position, forward), 0.2) + sceneRadius + BackdropLayout.gapBehindTarget
        let frameHeight = 2 * depth * tan(camera.lens.verticalFOV / 2) * (1.02 + margin)
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

    /// Three-point lighting placed relative to the camera, so it looks the same from
    /// any angle: a key light, a fill light, and a rim light from behind that separates
    /// the scene from the backdrop. The preset sets each light's color, strength, and
    /// direction.
    static func lights(for preset: LightingPreset, camera: CaptureCamera, center: SIMD3<Float>) -> [Entity] {
        let right = camera.orientation.act([1, 0, 0])
        var back = center - camera.position
        back.y = 0
        back = simd_length(back) > 1e-3 ? simd_normalize(back) : [0, 0, -1]

        func light(_ spec: LightingPreset.Light, shadows: Bool) -> DirectionalLight {
            let light = DirectionalLight()
            light.light.intensity = spec.intensity
            light.light.color = color(spec.color)
            if shadows { light.shadow = DirectionalLightComponent.Shadow() }
            // A directional light shines down its -Z axis, so +Z points back at where it comes from.
            light.orientation = .upright(facing: -back * spec.front + right * spec.side + [0, spec.up, 0])
            return light
        }

        return [
            light(preset.key, shadows: preset.keyCastsShadows),
            light(preset.fill, shadows: false),
            light(preset.rim, shadows: false)
        ]
    }

    private static func color(_ rgb: SIMD3<Float>) -> PlatformColor {
        PlatformColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }

    /// The preset's sky-to-ground gradient, used as image-based lighting.
    static func makeEnvironment(for preset: LightingPreset) -> CGImage {
        let width = 512
        let height = 256
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let stops = [preset.environment.top, preset.environment.middle, preset.environment.bottom]
        let colors = stops.map { CGColor(srgbRed: CGFloat($0.x), green: CGFloat($0.y), blue: CGFloat($0.z), alpha: 1) } as CFArray
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
        return try makeImage(bytes: bytes, width: width, height: height)
    }

    /// An image from BGRA pixels, as read from the render texture.
    fileprivate static func makeImage(bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        let bytesPerRow = width * 4
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

// MARK: - Sequences

extension CompositionRenderer {
    /// Renders many frames with one renderer, lighting environment, and target, for the
    /// animatic. Setting those up is the slow part of a single render; here it happens once.
    final class Sequence {
        private let base = CompositionRenderer()
        private let renderer: RealityRenderer
        private let texture: any MTLTexture
        private let output: RealityRenderer.CameraOutput
        private let camera = PerspectiveCamera()
        /// Holds each frame's scene, backdrop, and lights; emptied between frames.
        private let stage = Entity()
        private let backdrop: ModelEntity
        private let backdropPose: Transform?
        private let background: CGImage
        private let lighting: LightingPreset
        private let look: CaptureLook
        private var backgroundTexture: TextureResource?

        init(backdrop: ModelEntity, backdropPose: Transform?, background: CGImage, lighting: LightingPreset,
             look: CaptureLook, width: Int, height: Int) async throws {
            guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.metalUnavailable }
            self.backdrop = backdrop
            self.backdropPose = backdropPose
            self.background = background
            self.lighting = lighting
            self.look = look

            renderer = try RealityRenderer()
            camera.camera.near = 0.01
            camera.camera.far = 100
            renderer.entities.append(contentsOf: [stage, camera])
            renderer.activeCamera = camera
            renderer.lighting.resource = try await EnvironmentResource(
                equirectangular: CompositionRenderer.makeEnvironment(for: lighting))
            renderer.lighting.intensityExponent = lighting.environmentExposure
            renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
            renderer.cameraSettings.antialiasing = .multisample4X

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.renderFailed }
            self.texture = texture
            output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        }

        /// - Parameter snapshot: From `CompositionRenderer.snapshot(of:)`; used directly, not copied.
        func render(snapshot: Entity, frame: CameraPath.Frame) async throws -> CGImage {
            stage.children.removeAll()

            let bounds = snapshot.visualBounds(relativeTo: nil)
            let center = bounds.isEmpty ? snapshot.position : bounds.center
            let radius = max(bounds.isEmpty ? 0.3 : simd_length(bounds.extents) / 2, 0.05)

            camera.camera.fieldOfViewInDegrees = frame.verticalFOV * 180 / .pi
            camera.position = frame.camera.position
            camera.orientation = frame.camera.orientation
            var lensPlan = look.depthOfField.map {
                LensPlan($0, subject: snapshot, camera: frame.camera, verticalFOV: frame.verticalFOV,
                         sampleLimit: Self.animaticSampleLimit)
            }

            if backgroundTexture == nil {
                backgroundTexture = try await TextureResource(image: background, withName: nil,
                                                              options: .init(semantic: .color))
            }
            let backdropCopy = try await base.makeBackdrop(
                live: backdrop, image: background, pose: backdropPose, camera: frame.camera,
                sceneCenter: center, sceneRadius: radius, tint: lighting.backdropTint, texture: backgroundTexture,
                margin: lensPlan?.backdropMargin ?? 0)

            stage.addChild(snapshot)
            stage.addChild(backdropCopy)
            for light in CompositionRenderer.lights(for: lighting, camera: frame.camera, center: center) {
                stage.addChild(light)
            }

            let renderer = renderer, output = output
            func renderFrame() async throws {
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
            }

            let image: CGImage
            if lensPlan != nil {
                lensPlan?.backdropDepth = CompositionRenderer.depth(of: backdropCopy, from: frame.camera)
                // Taken out while in use, so its large buffers are changed in place rather than copied.
                var frameAccumulator = accumulator ?? Accumulator(width: texture.width, height: texture.height)
                accumulator = nil
                image = try await CompositionRenderer.renderThroughLens(lensPlan!, camera: camera, captureCamera: frame.camera,
                                                                       texture: texture, accumulator: &frameAccumulator,
                                                                       render: renderFrame)
                accumulator = frameAccumulator
            } else {
                try await renderFrame()
                image = try CompositionRenderer.makeImage(from: texture)
            }
            return FilmFinisher.finish(image, look: look, lighting: lighting)
        }

        /// Lens blur in the animatic uses fewer renders per frame than a photo, so it stays
        /// quick enough to export; the smoothing hides most of the difference.
        static let animaticSampleLimit = 10
        private var accumulator: Accumulator?
    }
}
