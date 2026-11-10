//
//  CatalogThumbnails.swift
//  Storyboard3DWorkspace
//

import Metal
import RealityKit
import UIKit

/// Studio-lit, transparent-background renders of each built-in object, for the
/// Objects tab's library tray.
///
/// The images ship with the app (Resources/Thumbnails/catalog-<kind>.png) and are only
/// loaded at runtime. Rendering them live froze the app: the offscreen render waits on
/// the main thread, which is also where its completion arrives. To regenerate them after
/// changing an object, run `CatalogThumbnailTests.regenerateBundledThumbnails`.
@Observable
final class CatalogThumbnails {
    private(set) var images: [SampleObjectCatalog.Kind: UIImage] = [:]

    static let pixelSize = 320

    static func resourceName(for kind: SampleObjectCatalog.Kind) -> String { "catalog-\(kind.rawValue)" }

    func loadIfNeeded() {
        guard images.count < SampleObjectCatalog.Kind.allCases.count else { return }
        for kind in SampleObjectCatalog.Kind.allCases where images[kind] == nil {
            if let url = Bundle.main.url(forResource: Self.resourceName(for: kind), withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
                images[kind] = image
            }
        }
    }

    /// A three-quarter view from slightly above, like a product shot. Used only to
    /// regenerate the bundled images, never while the app is running.
    static func render(_ kind: SampleObjectCatalog.Kind) async throws -> CGImage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw CompositionRenderer.RenderError.metalUnavailable }
        let renderer = try RealityRenderer()

        let object = SampleObjectCatalog.make(kind, tint: nil)
        let bounds = object.visualBounds(relativeTo: nil)
        let center = bounds.center
        let radius = max(simd_length(bounds.extents) / 2, 0.01)

        let camera = PerspectiveCamera()
        let fov: Float = 28
        camera.camera.fieldOfViewInDegrees = fov
        camera.camera.near = 0.005
        camera.camera.far = 10
        let direction = simd_normalize(SIMD3<Float>(0.85, 0.62, 1.15))
        let distance = radius / sin(fov / 2 * .pi / 180) * 1.02
        let position = center + direction * distance
        camera.look(at: center, from: position, relativeTo: nil)

        let captureCamera = CaptureCamera(position: position, orientation: camera.orientation, lens: .normal)
        renderer.entities.append(contentsOf: [object, camera]
                                 + CompositionRenderer.lights(for: .studio, camera: captureCamera, center: center))
        renderer.activeCamera = camera
        renderer.lighting.resource = try await EnvironmentResource(
            equirectangular: CompositionRenderer.makeEnvironment(for: .studio))
        renderer.lighting.intensityExponent = LightingPreset.studio.environmentExposure
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        renderer.cameraSettings.antialiasing = .multisample4X

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: pixelSize,
                                                                  height: pixelSize, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw CompositionRenderer.RenderError.renderFailed }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        try renderer.update(0)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { _ in continuation.resume() })
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let bytesPerRow = pixelSize * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * pixelSize)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, pixelSize, pixelSize), mipmapLevel: 0)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: pixelSize, height: pixelSize, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                           | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw CompositionRenderer.RenderError.renderFailed }
        return image
    }
}
