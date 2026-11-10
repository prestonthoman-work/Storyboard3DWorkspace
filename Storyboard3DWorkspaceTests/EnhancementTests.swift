//
//  EnhancementTests.swift
//  Storyboard3DWorkspaceTests
//

import AVFoundation
import CoreGraphics
import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

@MainActor
struct CameraPathTests {
    private let a = CaptureCamera(position: [0, 1, 0], orientation: simd_quatf(angle: 0, axis: [0, 1, 0]), lens: .wide)
    private let b = CaptureCamera(position: [1, 1, 0], orientation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]), lens: .portrait)

    @Test func holdsAtTheEndsAndEasesBetween() throws {
        let path = CameraPath(stops: [.init(time: 2, camera: b), .init(time: 0, camera: a)])
        #expect(try #require(path.frame(at: -1)).camera.position == a.position)
        #expect(try #require(path.frame(at: 5)).camera.position == b.position)

        let middle = try #require(path.frame(at: 1))
        #expect(abs(middle.camera.position.x - 0.5) < 1e-5)
        let quarter = try #require(path.frame(at: 0.5))
        #expect(quarter.camera.position.x < 0.25)          // eased, like the objects
        #expect(middle.camera.lens == .wide)               // sized for the wider lens
        let fov = (CaptureLens.wide.verticalFOV + CaptureLens.portrait.verticalFOV) / 2
        #expect(abs(middle.verticalFOV - fov) < 1e-5)
    }

    @Test func emptyPathHasNoFrames() {
        #expect(CameraPath(stops: []).frame(at: 0) == nil)
    }
}

@MainActor
struct SlideCaptionTests {
    @Test func captionReadsLikeAStoryboardPanel() {
        #expect(SlideCaption.caption(number: 3, shotType: .closeUp, note: " Car pulls in ") == "SHOT 03  ·  CU  ·  Car pulls in")
        #expect(SlideCaption.caption(number: 12, shotType: nil, note: "") == "SHOT 12")
    }

    @Test func burningKeepsTheFrameSize() throws {
        let context = try #require(CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let burned = SlideCaption.burn("SHOT 01", into: image)
        #expect(burned.width == 320 && burned.height == 180)
    }
}

/// Serialized: these share the projects storage override.
@MainActor
@Suite(.serialized)
struct EnhancementAppTests {
    init() throws {
        let storage = FileManager.default.temporaryDirectory.appending(path: "EnhancementTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        ProjectStore.storageOverride = storage
    }

    private func solidImage() -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        return context.makeImage()!
    }

    @Test func onionSkinGhostsWhatMovedAndStaysOutOfPhotos() async throws {
        let app = AppModel()
        await app.createProject(from: .streetCorner)
        app.immersiveSpaceState = .open
        defer { app.immersiveSpaceState = .closed }
        let preference = app.showsOnionSkin
        app.showsOnionSkin = true
        defer { app.showsOnionSkin = preference }

        // Keyframe 2 is selected; only the car moved since keyframe 1.
        let car = try #require(app.objects.first { $0.name == "Hero Car" }?.id)
        let ghosts = try #require(app.onionSkinPoses)
        #expect(Set(ghosts.keys) == [car])

        app.workspace.setOnionSkin(ghosts)
        #expect(app.workspace.onionRoot.children.count == 1)
        let snapshot = CompositionRenderer.snapshot(of: app.workspace.baseAnchor)
        #expect(snapshot.findEntity(named: WorkspaceScene.onionSkinName) == nil)

        app.selectKeyframe(app.animator.timeline.keyframes[0])
        #expect(app.onionSkinPoses == nil)              // nothing before the first keyframe
        app.workspace.setOnionSkin(nil)
        #expect(app.workspace.onionRoot.children.isEmpty)
    }

    @Test func animaticNeedsAPhotographedKeyframe() async throws {
        let app = AppModel()
        await app.createProject(from: .streetCorner)
        await app.useBuiltInSky()
        #expect(!app.canExportAnimatic)
        let camera = CaptureCamera.looking(from: [0, 1.3, 0.6], at: app.workspace.baseAnchor.position(relativeTo: nil),
                                           lens: .standard)
        app.photos.add(solidImage(), lens: .standard, keyframe: app.animator.timeline.keyframes[0].id, camera: camera)
        #expect(app.canExportAnimatic)
    }

    @Test func animaticRendersAVideoOfTheMove() async throws {
        let app = AppModel()
        await app.createProject(from: .streetCorner)
        await app.useBuiltInSky()
        let target = app.workspace.baseAnchor.position(relativeTo: nil)
        let keyframes = app.animator.timeline.keyframes
        app.photos.add(solidImage(), lens: .wide, keyframe: keyframes[0].id,
                       camera: .looking(from: target + [-0.4, 0.3, 0.5], at: target, lens: .wide))
        app.photos.add(solidImage(), lens: .normal, keyframe: keyframes[1].id,
                       camera: .looking(from: target + [0.4, 0.2, 0.4], at: target, lens: .normal))

        app.exportAnimatic()
        for _ in 0..<600 where app.isExporting || app.exportedFile == nil && app.exportError == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(app.exportError == nil)
        let file = try #require(app.exportedFile)
        let duration = try await AVURLAsset(url: file.url).load(.duration).seconds
        // One second of motion plus the half-second hold on the last shot.
        #expect(abs(duration - 1.5) < 0.15)
    }
}
