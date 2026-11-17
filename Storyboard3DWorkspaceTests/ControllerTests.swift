//
//  ControllerTests.swift
//  Storyboard3DWorkspaceTests
//

import CoreGraphics
import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

extension SharedStateTests {
    /// The capture camera and photo sync controllers, on their own and through `AppModel`.
    @MainActor
    @Suite(.serialized)
    struct ControllerTests {
        init() throws {
            let storage = FileManager.default.temporaryDirectory.appending(path: "ControllerTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            ProjectStore.storageOverride = storage
        }

        private func solidImage() -> CGImage {
            let context = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
            return context.makeImage()!
        }

        @Test func theSelfTimerCountsDownAndCanBeCancelled() async throws {
            let capture = CaptureController(workspace: WorkspaceScene())
            var fired = false
            capture.startCountdown { fired = true }
            try await Task.sleep(for: .milliseconds(100))
            #expect(capture.countdown == 3)
            #expect(capture.isBusy)
            capture.cancelCountdown()
            #expect(capture.countdown == nil)
            #expect(!capture.isBusy)
            try await Task.sleep(for: .seconds(1.2))
            #expect(!fired)
        }

        @Test func settingsMarkTheProjectChangedOnlyWhenTheyChange() async throws {
            let app = AppModel()
            await app.createProject()
            #expect(app.saveNow())
            app.captureLook = app.captureLook                // no change
            #expect(app.saveNow())
            app.captureLens = CaptureLens(70)
            #expect(app.capture.lens == CaptureLens(70))
            #expect(app.saveNow())
            let project = try #require(app.currentProject)
            let reopened = AppModel()
            #expect(await reopened.openProject(try #require(reopened.projects.first { $0.id == project.id })))
            #expect(reopened.captureLens == CaptureLens(70))
        }

        @Test func photosOfAChangedKeyframeMoveToTheLibraryWhenSyncIsOff() async throws {
            let app = AppModel()
            await app.createProject()
            let preference = app.keepPhotosInSync
            app.keepPhotosInSync = false
            defer { app.keepPhotosInSync = preference }
            app.placeCatalogObject(.tree)
            app.addKeyframe()
            let keyframe = try #require(app.animator.selectedKeyframeID)
            let photo = try #require(app.photos.add(solidImage(), lens: .normal, keyframe: keyframe))

            let (jobs, detached) = app.photoSync.prepare([keyframe], timeline: app.animator.timeline, canRender: true)
            #expect(jobs.isEmpty)
            #expect(detached.count == 1 && detached[0].count == 1)
            #expect(app.photos.photo(photo.id)?.keyframeID == nil)
        }

        @Test func photosWithASavedAngleAreQueuedForRerendering() async throws {
            let app = AppModel()
            await app.createProject()
            app.placeCatalogObject(.tree)
            app.addKeyframe()
            let keyframe = try #require(app.animator.selectedKeyframeID)
            let camera = CaptureCamera.looking(from: [0, 1.3, 0.6], at: app.workspace.baseAnchor.position(relativeTo: nil),
                                               lens: .standard)
            app.photos.add(solidImage(), lens: .standard, keyframe: keyframe, camera: camera)
            app.photos.add(solidImage(), lens: .standard, keyframe: keyframe)          // no angle: can't re-render

            let (jobs, detached) = app.photoSync.prepare([keyframe], timeline: app.animator.timeline, canRender: true)
            #expect(jobs.count == 1)
            #expect(detached.isEmpty)
            #expect(app.photos.photos(for: keyframe).count == 1)
        }
    }
}
