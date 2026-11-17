//
//  CameraControlTests.swift
//  Storyboard3DWorkspaceTests
//

import CoreGraphics
import Foundation
import RealityKit
import Testing
import UIKit
@testable import Storyboard3DWorkspace

@MainActor
struct CameraControlTests {
    // MARK: Helpers

    private func solidImage(width: Int, height: Int, gray: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// Gray levels (0–255) of an image, row by row from the top, at a size that's easy to check.
    private func grays(of image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    /// A placed object: a box, or with `depth`, a flat card facing the camera.
    private func placedBox(_ id: ObjectID, size: Float, depth: Float? = nil, at position: SIMD3<Float>) -> Entity {
        let object = Entity()
        object.components.set(PlacedObjectComponent(id: id))
        let box = ModelEntity(mesh: .generateBox(size: [size, size, depth ?? size]),
                              materials: [UnlitMaterial(color: .white)])
        object.addChild(box)
        object.position = position
        return object
    }

    // MARK: Lenses

    @Test func lensesReadProjectsSavedWithTheFourFixedLenses() throws {
        let decoded = try JSONDecoder().decode([CaptureLens].self, from: Data("[24, 35, 50, 85]".utf8))
        #expect(decoded == [.wide, .standard, .normal, .portrait])
        #expect(String(decoding: try JSONEncoder().encode(CaptureLens(70)), as: UTF8.self) == "70")
        // Out-of-range values are kept to the lenses the app offers.
        #expect(try JSONDecoder().decode(CaptureLens.self, from: Data("400".utf8)).focalLength == 200)
        #expect(CaptureLens(5).focalLength == CaptureLens.range.lowerBound)
    }

    @Test func longerLensesSeeLess() {
        #expect(CaptureLens(100).verticalFOV < CaptureLens.normal.verticalFOV)
        #expect(CaptureLens(14).horizontalFOV > CaptureLens.wide.horizontalFOV)
        #expect(CaptureLens(70).label == "70 mm")
    }

    // MARK: Frame shapes

    @Test func narrowFormatsArePillarboxed() {
        #expect(abs(FrameFormat.vertical.pillarFraction - 0.342) < 0.002)
        #expect(abs(FrameFormat.academy.pillarFraction - 0.125) < 0.002)
        #expect(FrameFormat.vertical.matteFraction == 0)
        #expect(FrameFormat.scope.pillarFraction == 0)

        let white = solidImage(width: 320, height: 180, gray: 1)
        let finished = FilmFinisher.finish(white, look: CaptureLook(format: .vertical, isFilmGraded: false), lighting: .studio)
        let pixels = grays(of: finished, width: 32, height: 18)
        let middleRow = 9 * 32
        #expect(pixels[middleRow + 1] < 10)      // left bar
        #expect(pixels[middleRow + 30] < 10)     // right bar
        #expect(pixels[middleRow + 16] > 245)    // picture
    }

    @Test func looksSavedBeforeDepthOfFieldStaySharp() throws {
        let look = try JSONDecoder().decode(CaptureLook.self, from: Data(#"{"format":"scope","isFilmGraded":true}"#.utf8))
        #expect(look.format == .scope)
        #expect(look.depthOfField == nil)
    }

    // MARK: Depth of field

    @Test func everyApertureViewLooksAtTheFocusPoint() {
        let camera = CaptureCamera(position: [0.1, 1.2, 0.5], orientation: simd_quatf(angle: 0.3, axis: [0, 1, 0]), lens: .normal)
        let depthOfField = DepthOfField(fStop: 2)
        let radius = depthOfField.apertureRadius(for: camera.lens)
        #expect(abs(radius - 0.0125) < 1e-6)      // a 50 mm f/2 lens opens 25 mm across

        let focus = camera.position + camera.orientation.act([0, 0, -1]) * 0.4
        let views = CompositionRenderer.apertureViews(of: camera, focusDistance: 0.4, radius: radius, count: 24)
        #expect(views.count == 24)
        var widest: Float = 0
        for view in views {
            let offset = view.position - camera.position
            #expect(abs(simd_dot(offset, camera.orientation.act([0, 0, -1]))) < 1e-5)   // across the lens, not along it
            #expect(simd_length(offset) <= radius * 1.0001)
            widest = max(widest, simd_length(offset))
            let ray = view.orientation.act([0, 0, -1])
            let hit = view.position + ray * simd_length(focus - view.position)
            #expect(simd_length(hit - focus) < 1e-4)
        }
        #expect(widest > radius * 0.8)
    }

    @Test func focusFindsWhatIsAtTheCenterOrTheChosenObject() {
        let scene = Entity()
        let near = UUID(), far = UUID()
        scene.addChild(placedBox(near, size: 0.05, at: [0, 0, -0.4]))
        scene.addChild(placedBox(far, size: 0.05, at: [0.2, 0, -0.8]))
        let camera = CaptureCamera(position: .zero, orientation: simd_quatf(angle: 0, axis: [0, 1, 0]), lens: .normal)

        #expect(abs(CompositionRenderer.focusDistance(for: DepthOfField(), in: scene, camera: camera) - 0.4) < 1e-3)
        #expect(abs(CompositionRenderer.focusDistance(for: DepthOfField(focusObject: far), in: scene, camera: camera) - 0.8) < 1e-3)

        // Nothing at the center: the object nearest the middle of the picture is used.
        scene.children.first?.position = [0.5, 0, -0.4]
        #expect(abs(CompositionRenderer.focusDistance(for: DepthOfField(), in: scene, camera: camera) - 0.8) < 1e-3)
    }

    @Test func depthOfFieldBlursWhatIsOutOfFocus() async throws {
        // A card in focus on the left and one far behind it on the right, against a plain backdrop.
        let scene = Entity()
        let near = UUID()
        scene.addChild(placedBox(near, size: 0.06, depth: 0.001, at: [-0.08, 0, -0.5]))
        scene.addChild(placedBox(UUID(), size: 0.12, depth: 0.001, at: [0.35, 0, -1.6]))
        let backdrop = ModelEntity(mesh: .generatePlane(width: 1, height: 1), materials: [UnlitMaterial(color: .gray)])
        backdrop.isEnabled = false
        let background = solidImage(width: 64, height: 36, gray: 0.3)
        let camera = CaptureCamera(position: .zero, orientation: simd_quatf(angle: 0, axis: [0, 1, 0]), lens: .normal)

        let renderer = CompositionRenderer()
        let snapshot = CompositionRenderer.snapshot(of: scene)
        let sharp = try await renderer.render(snapshot: snapshot, backdrop: backdrop, backdropPose: nil, background: background,
                                              camera: camera, lighting: .studio, look: CaptureLook(isFilmGraded: false))
        var blurredLook = CaptureLook(isFilmGraded: false)
        blurredLook.depthOfField = DepthOfField(fStop: 2.8, focusObject: near)
        let blurred = try await renderer.render(snapshot: snapshot, backdrop: backdrop, backdropPose: nil, background: background,
                                                camera: camera, lighting: .studio, look: blurredLook)
        #expect(blurred.width == CompositionRenderer.outputWidth && blurred.height == CompositionRenderer.outputHeight)

        // Compare each half of the frame with the sharp render: the card in focus (left) stays
        // the same, the far one (right) spreads out.
        let width = 128, height = 72
        let a = grays(of: sharp, width: width, height: height)
        let b = grays(of: blurred, width: width, height: height)
        var left = 0, right = 0
        for y in 0..<height {
            for x in 0..<width {
                // Count clearly changed pixels; renders differ by a level or so of noise anyway.
                guard abs(Int(a[y * width + x]) - Int(b[y * width + x])) > 20 else { continue }
                if x < width / 2 { left += 1 } else { right += 1 }
            }
        }
        #expect(right > 25)
        #expect(left < right / 5)
    }
}
