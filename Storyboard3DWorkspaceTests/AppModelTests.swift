//
//  AppModelTests.swift
//  Storyboard3DWorkspaceTests
//

import AVFoundation
import CoreGraphics
import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

/// End-to-end checks through `AppModel`. Every test runs against its own temporary
/// storage folder, so real projects are never read or changed. Serialized because the
/// storage location is shared.
@MainActor
@Suite(.serialized)
struct AppModelTests {
    let storage: URL

    init() throws {
        storage = FileManager.default.temporaryDirectory.appending(path: "AppModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        ProjectStore.storageOverride = storage
    }

    /// A fresh app with a new, open project.
    private func makeApp() async throws -> AppModel {
        let app = AppModel()
        await app.createProject()
        _ = try #require(app.currentProject)
        return app
    }

    private func solidImage() -> CGImage {
        let context = CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
        return context.makeImage()!
    }

    private func addObject(_ prompt: String, to app: AppModel) async throws -> (ObjectID, Entity) {
        app.objectPrompt = prompt
        await app.generateObject()
        let id = try #require(app.selectedObjectID)
        return (id, try #require(app.workspace.object(withID: id)))
    }

    /// Simulates grabbing an object, moving it, and letting go.
    private func move(_ entity: Entity, by dx: Float, in app: AppModel) async throws {
        app.manipulationBegan(on: entity)
        entity.position.x += dx
        app.sceneEdited()
        try await Task.sleep(for: .milliseconds(700))
    }

    // MARK: Undo

    @Test func undoRestoresAKeyframeAndReattachesItsPhoto() async throws {
        let app = try await makeApp()
        let preference = app.keepPhotosInSync
        app.keepPhotosInSync = false
        defer { app.keepPhotosInSync = preference }

        let (id, entity) = try await addObject("red house", to: app)
        app.addKeyframe()
        let keyframe = try #require(app.animator.selectedKeyframeID)
        let photo = try #require(app.photos.add(solidImage(), lens: .normal, keyframe: keyframe))
        let originalX = entity.position.x

        try await move(entity, by: 0.1, in: app)
        #expect(app.animator.selectedKeyframe?.poses[id]?.translation.x == originalX + 0.1)
        #expect(app.photos.photo(photo.id)?.assignment == .removed)

        app.undo()
        #expect(abs(entity.position.x - originalX) < 1e-6)
        #expect(app.photos.photo(photo.id)?.assignment == .keyframe(keyframe))
        #expect(app.photos.primaryPhoto(for: keyframe)?.id == photo.id)

        app.redo()
        #expect(abs(entity.position.x - (originalX + 0.1)) < 1e-6)
    }

    @Test func undoBringsBackADeletedObjectWithTheSameIdentity() async throws {
        let app = try await makeApp()
        let (id, _) = try await addObject("pine tree", to: app)
        app.addKeyframe()
        app.deleteSelectedObject()
        #expect(app.objects.isEmpty)
        app.undo()
        #expect(app.objects.map(\.id) == [id])
        #expect(app.animator.timeline.keyframes.first?.poses[id] != nil)
    }

    @Test func baseChangesAreUndoable() async throws {
        let app = try await makeApp()
        app.applyBaseTemplate(.sand)
        #expect(app.base.name == "Sand")
        app.undo()
        #expect(app.base.name == "Grass")
    }

    // MARK: Editing objects

    @Test func recolorUpdatesAutomaticNamesButKeepsCustomOnes() async throws {
        let app = try await makeApp()
        let (id, entity) = try await addObject("house", to: app)
        app.recolorSelectedObject("blue")
        #expect(app.selectedObject?.name == "Blue House")
        #expect(app.workspace.object(withID: id) === entity)
        app.undo()
        #expect(app.selectedObject?.name == "House")

        app.renameObject(id, to: "Grandma's Place")
        app.recolorSelectedObject("yellow")
        #expect(app.selectedObject?.name == "Grandma's Place")
        #expect(app.selectedObject?.recipe.colorName == "yellow")
    }

    @Test func replaceKeepsPlaceAndKeyframes() async throws {
        let app = try await makeApp()
        let (id, entity) = try await addObject("house", to: app)
        entity.position.x = 0.07
        app.addKeyframe()
        let keyframe = try #require(app.animator.selectedKeyframeID)
        app.objectPrompt = "blue car"
        await app.replaceSelectedObject()
        #expect(app.objects.map(\.id) == [id])
        #expect(app.selectedObject?.name == "Blue Car")
        #expect(app.workspace.object(withID: id)?.position.x == 0.07)
        #expect(app.animator.timeline.keyframe(keyframe)?.poses[id] != nil)
    }

    @Test func objectsListShowsKeyframeMembership() async throws {
        let app = try await makeApp()
        app.addKeyframe()                       // 1: empty
        app.addKeyframe()                       // 2: selected
        let (id, _) = try await addObject("house", to: app)
        try await Task.sleep(for: .milliseconds(500))   // auto-save puts the house in keyframe 2
        #expect(app.keyframeMembership(of: id) == "Keyframe 2")
    }

    // MARK: Keyframe editing

    @Test func editingBetweenKeyframesAddsOneThere() async throws {
        let app = try await makeApp()
        let (id, entity) = try await addObject("house", to: app)
        app.addKeyframe()
        try await move(entity, by: 0.2, in: app)
        app.addKeyframe()
        #expect(app.animator.timeline.keyframes.count == 2)

        app.scrubTimeline(to: 0.5)
        #expect(app.animator.selectedKeyframeID == nil)
        try await move(entity, by: 0.05, in: app)

        let keyframes = app.animator.timeline.keyframes
        #expect(keyframes.count == 3)
        #expect(abs(keyframes[1].time - 0.5) < 1e-9)
        #expect(app.animator.selectedKeyframeID == keyframes[1].id)
        #expect(keyframes[1].poses[id] != nil)

        app.undo()
        #expect(app.animator.timeline.keyframes.count == 2)
    }

    @Test func addKeyframeGoesAfterTheSelectedOne() async throws {
        let app = try await makeApp()
        app.addKeyframe()
        app.addKeyframe()
        let first = app.animator.timeline.keyframes[0]
        app.selectKeyframe(first)
        app.addKeyframe()
        let keyframes = app.animator.timeline.keyframes
        #expect(keyframes.count == 3)
        #expect(keyframes[0].id == first.id)
        #expect(app.animator.selectedKeyframeID == keyframes[1].id)
        #expect(keyframes.map(\.time) == [0, 1, 2])
    }

    @Test func deletingSelectsTheNeighbor() async throws {
        let app = try await makeApp()
        app.addKeyframe()
        app.addKeyframe()
        app.addKeyframe()
        let keyframes = app.animator.timeline.keyframes
        app.selectKeyframe(keyframes[2])
        app.deleteSelectedKeyframe()
        #expect(app.animator.selectedKeyframeID == keyframes[1].id)
        app.undo()
        #expect(app.animator.timeline.keyframes.count == 3)
    }

    @Test func retimeDragUndoesInOneStep() async throws {
        let app = try await makeApp()
        app.addKeyframe()
        app.addKeyframe()
        let second = app.animator.timeline.keyframes[1].id
        app.beginRetimingKeyframe()
        app.retimeKeyframe(second, to: 1.5)
        app.retimeKeyframe(second, to: 2.2)
        app.endRetimingKeyframe()
        #expect(abs(app.animator.timeline.duration - 2.2) < 1e-9)
        app.undo()
        #expect(app.animator.timeline.duration == 1)
    }

    // MARK: Naming

    @Test func repeatedObjectsGetNumberedNames() async throws {
        let app = try await makeApp()
        app.placeCatalogObject(.tree)
        app.placeCatalogObject(.tree)
        app.duplicateSelectedObject()
        #expect(app.objects.map(\.name) == ["Tree", "Tree 2", "Tree 3"])

        app.recolorSelectedObject("red")
        #expect(app.selectedObject?.name == "Red Tree")
        app.renameObject(try #require(app.selectedObjectID), to: "Hero Tree")
        app.recolorSelectedObject("blue")
        #expect(app.selectedObject?.name == "Hero Tree")   // custom names are kept
    }

    @Test func automaticNamesAreRecognized() {
        #expect(AppModel.isAutomaticName("Red House", for: "Red House"))
        #expect(AppModel.isAutomaticName("Red House 4", for: "Red House"))
        #expect(!AppModel.isAutomaticName("Grandma's House", for: "Red House"))
        #expect(AppModel.nameStem("Tree 12") == "Tree")
        #expect(AppModel.nameStem("Route 66 Diner") == "Route 66 Diner")
    }

    // MARK: Starters and the guide

    @Test func animatedStarterComesReadyToPlay() async throws {
        let app = AppModel()
        await app.createProject(from: .streetCorner)
        #expect(app.objects.count == StarterScene.streetCorner.placements.count)
        #expect(app.objects.contains { $0.name == "Hero Car" })
        let keyframes = app.animator.timeline.keyframes
        #expect(keyframes.count == 2)
        #expect(keyframes.map(\.shotType) == [.establishing, .wide])
        let car = try #require(app.objects.first { $0.name == "Hero Car" }?.id)
        let start = try #require(keyframes[0].poses[car]?.translation.x)
        let end = try #require(keyframes[1].poses[car]?.translation.x)
        #expect(end - start > 0.25)
        #expect(!app.canUndo)
        #expect(app.workflowStep == .takePhotos)
    }

    @Test func guideFollowsProgress() async throws {
        let app = try await makeApp()
        #expect(app.workflowStep == .addObjects)
        app.placeCatalogObject(.rock)
        #expect(app.workflowStep == .firstKeyframe)
        app.addKeyframe()
        #expect(app.workflowStep == .secondKeyframe)
        app.addKeyframe()
        #expect(app.workflowStep == .takePhotos)
        for keyframe in app.animator.timeline.keyframes {
            app.photos.add(solidImage(), lens: .normal, keyframe: keyframe.id)
        }
        #expect(app.workflowStep == .share)
    }

    @Test func shotTypesSaveAndUndo() async throws {
        let app = try await makeApp()
        app.addKeyframe()
        let id = try #require(app.animator.selectedKeyframeID)
        app.setShotType(.closeUp, forKeyframe: id)
        #expect(app.currentState().keyframes.first?.shotType == .closeUp)

        let data = try JSONEncoder().encode(app.currentState())
        let decoded = try JSONDecoder().decode(ProjectState.self, from: data)
        #expect(Keyframe(decoded.keyframes[0]).shotType == .closeUp)

        app.duplicateKeyframe(id)
        #expect(app.animator.timeline.keyframes.last?.shotType == .closeUp)
        app.undo()
        app.undo()
        #expect(app.animator.timeline.keyframe(id)?.shotType == nil)
    }

    // MARK: Photos follow their keyframes

    @Test func changingAKeyframeRerendersItsPhotosFromTheSavedAngle() async throws {
        let app = try await makeApp()
        await app.useBuiltInSky()
        let preference = app.keepPhotosInSync
        app.keepPhotosInSync = true
        defer { app.keepPhotosInSync = preference }

        let (_, entity) = try await addObject("house", to: app)
        app.addKeyframe()
        let keyframe = try #require(app.animator.selectedKeyframeID)
        let camera = CaptureCamera.looking(from: [0, 1.4, 0], at: app.workspace.baseAnchor.position(relativeTo: nil), lens: .standard)
        let original = try #require(app.photos.add(solidImage(), lens: .standard, keyframe: keyframe, camera: camera))

        try await move(entity, by: 0.05, in: app)
        for _ in 0..<50 where app.isUpdatingPhotos || app.photos.photos(for: keyframe).first?.id == original.id {
            try await Task.sleep(for: .milliseconds(100))
        }

        let updated = try #require(app.photos.photos(for: keyframe).first)
        #expect(updated.id != original.id)
        #expect(updated.camera == camera)
        #expect(app.photos.primaryPhoto(for: keyframe)?.id == updated.id)
        #expect(app.photos.photos.count == 1)

        // Undo returns the original photo along with the original pose.
        app.undo()
        #expect(app.photos.photos(for: keyframe).map(\.id) == [original.id])
    }

    @Test func retakeShootsFromTheSameSpotWithTheCurrentSettings() async throws {
        let app = try await makeApp()
        await app.useBuiltInSky()
        _ = try await addObject("house", to: app)
        app.addKeyframe()
        let keyframe = try #require(app.animator.selectedKeyframeID)
        let camera = CaptureCamera.looking(from: [0.2, 1.4, 0], at: app.workspace.baseAnchor.position(relativeTo: nil), lens: .standard)
        let original = try #require(app.photos.add(solidImage(), lens: .standard, keyframe: keyframe, camera: camera))
        app.focusedKeyframePhotoID = original.id

        app.captureLens = .portrait
        app.captureLighting = .night
        #expect(app.canRetakeFocusedPhoto)
        await app.retakeFocusedPhoto()

        let retaken = try #require(app.photos.primaryPhoto(for: keyframe))
        #expect(retaken.id != original.id)
        #expect(retaken.camera?.position == camera.position)
        #expect(retaken.camera?.lens == .portrait)
        #expect(retaken.lighting == .night)
        #expect(app.captureStatus == .retaken(keyframeNumber: 1))
    }

    // MARK: Saving and projects

    @Test func projectsSaveAndReopen() async throws {
        let app = try await makeApp()
        let (id, entity) = try await addObject("red house", to: app)
        entity.position.x = 0.05
        app.addKeyframe()
        let keyframe = try #require(app.animator.selectedKeyframeID)
        app.setNote("Opening shot", forKeyframe: keyframe)
        let camera = CaptureCamera.looking(from: [0, 1.4, 0], at: [0, 0.8, -1], lens: .wide)
        let photo = try #require(app.photos.add(solidImage(), lens: .wide, keyframe: keyframe, camera: camera, lighting: .goldenHour))
        app.baseWidth = 85
        app.captureLighting = .overcast
        app.saveNow()

        let relaunched = AppModel()
        await relaunched.openProject(try #require(relaunched.projects.first))
        #expect(relaunched.objects.map(\.id) == [id])
        #expect(relaunched.workspace.object(withID: id)?.position.x == 0.05)
        #expect(relaunched.baseWidth == 85)
        #expect(relaunched.captureLighting == .overcast)
        #expect(relaunched.animator.timeline.keyframes.map(\.note) == ["Opening shot"])
        let reloaded = try #require(relaunched.photos.photo(photo.id))
        #expect(reloaded.camera == camera && reloaded.lighting == .goldenHour)
        #expect(relaunched.photos.primaryPhoto(for: keyframe)?.id == photo.id)
        #expect(!relaunched.canUndo)
    }

    @Test func projectsCanBeRenamedDuplicatedAndDeleted() async throws {
        let app = try await makeApp()
        _ = try await addObject("house", to: app)
        let project = try #require(app.currentProject)
        app.renameProject(project.id, to: "Town Pitch")
        app.saveNow()

        app.duplicateProject(project.id)
        let copy = try #require(app.projects.first { $0.name == "Town Pitch Copy" })
        await app.openProject(copy)
        #expect(app.objects.map(\.name) == ["House"])

        await app.createProject()
        #expect(app.objects.isEmpty && app.animator.timeline.keyframes.isEmpty)
        #expect(app.projects.count == 3)

        app.deleteProject(copy.id)
        #expect(app.projects.count == 2)
        #expect(!app.projects.contains { $0.id == copy.id })
    }

    @Test func aSingleProjectFromEarlierVersionsMovesIntoTheList() throws {
        let legacy = storage.appending(path: "StoryboardProject")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        var state = ProjectState.empty
        state.base.diameterCentimeters = 95
        let saved = ProjectStore.SavedProject(state: state, captureLens: .wide, captureLighting: nil, backdrop: nil)
        try JSONEncoder().encode(saved).write(to: legacy.appending(path: "project.json"))

        let app = AppModel()
        #expect(app.projects.map(\.name) == ["My Storyboard"])
        #expect(!FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)))
    }

    // MARK: Exports

    @Test func slideshowUsesTheChosenTiming() async throws {
        let app = try await makeApp()
        let seconds = app.slideshowSecondsPerShot
        let crossfade = app.slideshowCrossfade
        defer {
            app.slideshowSecondsPerShot = seconds
            app.slideshowCrossfade = crossfade
        }

        for _ in 0..<2 {
            app.addKeyframe()
            app.photos.add(solidImage(), lens: .normal, keyframe: try #require(app.animator.selectedKeyframeID))
        }
        app.slideshowSecondsPerShot = 1.5
        app.slideshowCrossfade = false
        await app.exportSlideshow()
        let url = try #require(app.exportedFile?.url)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 3) < 0.05)
    }

    @Test func storyboardSheetPaginatesByLayout() async throws {
        let app = try await makeApp()
        let layout = app.sheetLayout
        defer { app.sheetLayout = layout }

        for _ in 0..<7 { app.addKeyframe() }
        for (choice, pages) in [(StoryboardSheetExporter.Layout.two, 4), (.six, 2), (.twelve, 1)] {
            app.sheetLayout = choice
            app.exportStoryboardSheet()
            let url = try #require(app.exportedFile?.url)
            let document = try #require(CGPDFDocument(url as CFURL))
            #expect(document.numberOfPages == pages)
        }
    }
}
