//
//  InteractionTests.swift
//  Storyboard3DWorkspaceTests
//

import CoreGraphics
import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

/// Telling taps from grabs, gentle snapping, the rings, and the backdrop preference.
@MainActor
struct InteractionTests {

    // MARK: Taps and grabs

    private let house = ObjectID()
    private let tree = ObjectID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    /// One quick pinch that doesn't move: how a tap reaches the arbiter on the headset.
    private func tap(_ arbiter: inout ObjectTapArbiter, _ object: ObjectID, at time: TimeInterval) -> ObjectTapArbiter.TapKind? {
        let start = t0.addingTimeInterval(time)
        arbiter.pinchBegan(on: object, at: start, position: .zero, scale: 1)
        return arbiter.pinchEnded(on: object, at: start.addingTimeInterval(0.08))
    }

    /// A pinch that carries the object `distance` meters. Returns what its release meant.
    @discardableResult
    private func drag(_ arbiter: inout ObjectTapArbiter, _ object: ObjectID, at time: TimeInterval,
                      distance: Float = 0.05, duration: TimeInterval = 0.3) -> ObjectTapArbiter.TapKind? {
        let start = t0.addingTimeInterval(time)
        arbiter.pinchBegan(on: object, at: start, position: .zero, scale: 1)
        arbiter.pinchMoved(on: object, position: [distance, 0, 0], scale: 1)
        return arbiter.pinchEnded(on: object, at: start.addingTimeInterval(duration))
    }

    @Test func deliberateDoubleTapIsRecognized() {
        var arbiter = ObjectTapArbiter()
        let first = tap(&arbiter, house, at: 0)
        let second = tap(&arbiter, house, at: 0.25)
        let third = tap(&arbiter, house, at: 0.5)
        #expect(first == .single)
        #expect(second == .double)
        // A third tap starts over rather than counting as another double.
        #expect(third == .single)
    }

    @Test func theTapGestureDoesNotCountATapTwice() {
        var arbiter = ObjectTapArbiter()
        let pinch = tap(&arbiter, house, at: 0)
        // The same tap, reported again by the tap gesture.
        let echo = arbiter.gestureTap(on: house, at: t0.addingTimeInterval(0.1))
        let second = tap(&arbiter, house, at: 0.3)
        #expect(pinch == .single)
        #expect(echo == nil)
        #expect(second == .double)
    }

    @Test func tapGesturesAloneStillMakeADoubleTap() {
        // If the system never reports a pinch, the tap gesture is enough.
        var arbiter = ObjectTapArbiter()
        let first = arbiter.gestureTap(on: house, at: t0)
        let second = arbiter.gestureTap(on: house, at: t0.addingTimeInterval(0.3))
        #expect(first == .single)
        #expect(second == .double)
    }

    @Test func releasingADragIsNotATap() {
        var arbiter = ObjectTapArbiter()
        let release = drag(&arbiter, house, at: 0)
        let echo = arbiter.gestureTap(on: house, at: t0.addingTimeInterval(0.3))
        #expect(release == nil)
        #expect(echo == nil)
    }

    @Test func letGoAndQuicklyGrabAgainNeverChangesColor() {
        var arbiter = ObjectTapArbiter()
        // Tap to select, then grab and move, let go, and immediately pinch again.
        let first = tap(&arbiter, house, at: 0)
        drag(&arbiter, house, at: 0.15)
        let regrab = tap(&arbiter, house, at: 0.55)
        // Another drag, then a quick pinch: still not a double-tap.
        drag(&arbiter, house, at: 0.75)
        let after = tap(&arbiter, house, at: 1.1)
        #expect(first == .single)
        #expect(regrab == .single)
        #expect(after == .single)
    }

    @Test func dragBetweenTapsCancelsTheDoubleTap() {
        var arbiter = ObjectTapArbiter()
        let first = tap(&arbiter, house, at: 0)
        drag(&arbiter, house, at: 0.1, duration: 0.12)
        let second = tap(&arbiter, house, at: 0.6)
        #expect(first == .single)
        #expect(second == .single)
    }

    @Test func tremorDoesNotTurnATapIntoADrag() {
        var arbiter = ObjectTapArbiter()
        arbiter.pinchBegan(on: house, at: t0, position: .zero, scale: 1)
        let becameDrag = arbiter.pinchMoved(on: house, position: [0.003, 0.001, 0], scale: 1)
        let release = arbiter.pinchEnded(on: house, at: t0.addingTimeInterval(0.1))
        #expect(!becameDrag)
        #expect(release == .single)
    }

    @Test func holdingStillIsAGrabNotATap() {
        var arbiter = ObjectTapArbiter()
        arbiter.pinchBegan(on: house, at: t0, position: .zero, scale: 1)
        let release = arbiter.pinchEnded(on: house, at: t0.addingTimeInterval(0.8))
        #expect(release == nil)
    }

    @Test func tapsOnDifferentObjectsAreNotADoubleTap() {
        var arbiter = ObjectTapArbiter()
        let first = tap(&arbiter, house, at: 0)
        let second = tap(&arbiter, tree, at: 0.2)
        #expect(first == .single)
        #expect(second == .single)
    }

    @Test func slowTapsAreTwoSingleTaps() {
        var arbiter = ObjectTapArbiter()
        let first = tap(&arbiter, house, at: 0)
        let second = tap(&arbiter, house, at: 0.7)
        #expect(first == .single)
        #expect(second == .single)
    }

    @Test func doubleTapThroughTheAppChangesTheColor() async throws {
        let app = AppModel()
        await app.createProject()
        app.placeCatalogObject(.house)
        let id = try #require(app.selectedObjectID)
        let entity = try #require(app.workspace.object(withID: id))
        let t = Date.now
        app.manipulationBegan(on: entity, at: t)
        app.manipulationEnded(on: entity, at: t.addingTimeInterval(0.08))
        app.manipulationBegan(on: entity, at: t.addingTimeInterval(0.25))
        app.manipulationEnded(on: entity, at: t.addingTimeInterval(0.33))
        #expect(app.objects.first { $0.id == id }?.recipe.colorName == SampleObjectCatalog.colorNames.first)
    }

    // MARK: Scenes and shot labels

    @Test func shotsAreLabeledByScene() {
        var timeline = KeyframeTimeline()
        let a = timeline.append([:]), b = timeline.append([:]), c = timeline.append([:]), d = timeline.append([:])
        #expect([a, b, c, d].map { timeline.label(of: $0.id)?.code } == ["1A", "1B", "1C", "1D"])
        timeline.setStartsScene(true, for: c.id)
        timeline.setSceneTitle("Kitchen, Night", forSceneContaining: d.id)
        #expect([a, b, c, d].map { timeline.labels[$0.id]?.code } == ["1A", "1B", "2A", "2B"])
        #expect(timeline.scenes.map(\.title) == ["", "Kitchen, Night"])
        #expect(timeline.scenes.map(\.shots.count) == [2, 2])
        // The first shot always starts scene 1.
        timeline.setStartsScene(true, for: a.id)
        timeline.setStartsScene(false, for: a.id)
        #expect(timeline.label(of: a.id)?.code == "1A")
    }

    @Test func letterLabelsKeepGoingPastZ() {
        #expect(ShotLabel.letters(for: 0) == "A")
        #expect(ShotLabel.letters(for: 25) == "Z")
        #expect(ShotLabel.letters(for: 26) == "AA")
        #expect(ShotLabel.letters(for: 27) == "AB")
    }

    @Test func deletingAScenesFirstShotKeepsTheScene() {
        var timeline = KeyframeTimeline()
        let a = timeline.append([:]), b = timeline.append([:]), c = timeline.append([:])
        timeline.setStartsScene(true, for: b.id)
        timeline.setSceneTitle("Street", forSceneContaining: b.id)
        timeline.remove(b.id)
        #expect(timeline.label(of: c.id)?.code == "2A")
        #expect(timeline.scenes.last?.title == "Street")
        #expect(timeline.label(of: a.id)?.code == "1A")
    }

    @Test func scenesAreSavedWithTheProject() {
        var keyframe = Keyframe(time: 1, poses: [:])
        keyframe.startsScene = true
        keyframe.sceneTitle = "Rooftop"
        let restored = Keyframe(ProjectState.KeyframeState(keyframe))
        #expect(restored.startsScene)
        #expect(restored.sceneTitle == "Rooftop")
    }

    // MARK: Base and backdrop

    @Test func theBaseSlidesAlongTheTableByItsHandle() {
        let scene = WorkspaceScene()
        let start = scene.baseAnchor.position(relativeTo: nil)
        scene.dragBase(to: [0, 1, 0], keepingHeight: true)
        scene.dragBase(to: [0.2, 1.3, -0.1], keepingHeight: true)
        scene.endBaseDrag()
        let moved = scene.baseAnchor.position(relativeTo: nil)
        #expect(simd_distance(moved, start + [0.2, 0, -0.1]) < 1e-5)
    }

    @Test func theMoveHandleNeverAppearsInPhotos() {
        let scene = WorkspaceScene()
        let snapshot = CompositionRenderer.snapshot(of: scene.baseAnchor)
        #expect(scene.baseAnchor.findEntity(named: WorkspaceScene.moveGripName) != nil)
        #expect(snapshot.findEntity(named: WorkspaceScene.moveGripName) == nil)
    }

    @Test func theBackdropKeepsToTheBaseNotTheObjects() {
        let scene = WorkspaceScene()
        scene.setBase(BaseTemplateBuilder.make(.grass), size: 0.6)
        let footprint = scene.backdrop.components[ViewerFacingBackdropComponent.self]?.footprint
        #expect(footprint?.radius == 0.3)
        // Moving an object far off the base doesn't change what the backdrop keeps behind.
        let house = scene.addObject(SampleObjectCatalog.make(.house, tint: nil), name: "House")
        house.position = [1.5, 0, 0]
        #expect(scene.backdrop.components[ViewerFacingBackdropComponent.self]?.footprint?.radius == 0.3)
    }

    // MARK: Position snapping

    @Test func snappingOnlyOffersCloseTargets() {
        var snapper = AlignmentSnapper()
        let neighbors: [AlignmentSnapper.Neighbor] = [(tree, [0.1, 0.2])]
        snapper.begin(at: [0, 0], neighbors: neighbors)
        let result2 = snapper.update(position: [0.094, 0], neighbors: neighbors)
        #expect(result2.isEmpty)
        let targets = snapper.update(position: [0.097, 0], neighbors: neighbors)
        #expect(targets[.x]?.value == 0.1)
        #expect(targets[.z] == nil)
        #expect(snapper.snapped([0.097, 0.05]) == [0.1, 0.05])
    }

    @Test func aTargetHoldsUntilYouPullAwayThenLetsGo() {
        var snapper = AlignmentSnapper()
        let neighbors: [AlignmentSnapper.Neighbor] = [(tree, [0.1, 0.2])]
        snapper.begin(at: [0, 0], neighbors: neighbors)
        snapper.update(position: [0.098, 0], neighbors: neighbors)
        // Past the capture distance but inside the release distance: still offered (no flicker).
        let result3 = snapper.update(position: [0.0945, 0], neighbors: neighbors)
        #expect(result3[.x] != nil)
        // Pulled clear: released.
        let result4 = snapper.update(position: [0.092, 0], neighbors: neighbors)
        #expect(result4[.x] == nil)
    }

    @Test func nearbyTargetsDoNotTradePlacesOnTremor() {
        var snapper = AlignmentSnapper()
        let a = ObjectID(), b = ObjectID()
        let neighbors: [AlignmentSnapper.Neighbor] = [(a, [0.100, 0.3]), (b, [0.103, -0.3])]
        snapper.begin(at: [0, 0], neighbors: neighbors)
        let result5 = snapper.update(position: [0.1012, 0], neighbors: neighbors)
        #expect(result5[.x]?.object == a)
        // Slightly closer to b now, but not by the switch margin.
        let result6 = snapper.update(position: [0.1018, 0], neighbors: neighbors)
        #expect(result6[.x]?.object == a)
        // Clearly closer to b.
        let result7 = snapper.update(position: [0.1031, 0], neighbors: neighbors)
        #expect(result7[.x]?.object == b)
    }

    @Test func nudgingAnAlignedObjectIsNotPulledBack() {
        var snapper = AlignmentSnapper()
        let neighbors: [AlignmentSnapper.Neighbor] = [(tree, [0.1, 0.2])]
        // Picked up already lined up with the tree on x.
        snapper.begin(at: [0.1, 0], neighbors: neighbors)
        let result8 = snapper.update(position: [0.102, 0], neighbors: neighbors)
        #expect(result8.isEmpty)
        #expect(snapper.snapped([0.102, 0]) == [0.102, 0])
        // Moved well away and back: the tree is offered again.
        snapper.update(position: [0.13, 0], neighbors: neighbors)
        let result9 = snapper.update(position: [0.102, 0], neighbors: neighbors)
        #expect(result9[.x] != nil)
    }

    @Test func rotationDetentsAreSoft() {
        let near = RotationDetent.apply(.pi / 2 + 0.03)
        #expect(abs(near.angle - .pi / 2) < 1e-5)
        #expect(near.step == 6)
        // Between steps, the angle is left alone.
        let between = RotationDetent.apply(.pi / 2 + 0.12)
        #expect(between.angle == .pi / 2 + 0.12)
        #expect(between.step == nil)
    }

    // MARK: Moving and rotating in the scene

    private func sceneWithSelectedHouse() -> (WorkspaceScene, Entity) {
        let scene = WorkspaceScene()
        let object = scene.addObject(SampleObjectCatalog.make(.house, tint: nil), name: "House")
        scene.showSelection(on: object)
        // The follow system isn't running here, so put the handles at the object by hand.
        scene.handles.root.position = object.position(relativeTo: nil)
        return (scene, object)
    }

    @Test func grabbingCanOnlyMoveAndResizeNeverRotate() throws {
        let (_, object) = sceneWithSelectedHouse()
        let manipulation = try #require(object.components[ManipulationComponent.self])
        #expect(manipulation.dynamics.primaryRotationBehavior == .none)
        #expect(manipulation.dynamics.secondaryRotationBehavior == .none)
        #expect(manipulation.dynamics.translationBehavior == .unconstrained)
        #expect(manipulation.dynamics.scalingBehavior == .unconstrained)
    }

    @Test func lettingGoNearAGuideLinesUpPositionButKeepsRotation() {
        let scene = WorkspaceScene()
        let house = scene.addObject(SampleObjectCatalog.make(.house, tint: nil), name: "House")
        let tree = scene.addObject(SampleObjectCatalog.make(.tree, tint: nil), name: "Tree")
        tree.position = [0.12, 0, -0.1]
        house.position = [0, 0, 0.1]
        let turned = simd_quatf(angle: 0.37, axis: [0, 1, 0])
        house.orientation = turned

        // Centers on the base (the house's center may sit off its origin).
        func baseCenter(_ entity: Entity) -> SIMD3<Float> {
            scene.objectsContainer.convert(position: WorkspaceScene.center(of: entity), from: nil)
        }
        scene.beginMove(of: house)
        // Carried to within 3 mm of the tree's line.
        let treeCenter = baseCenter(tree).x
        house.position.x += treeCenter + 0.003 - baseCenter(house).x
        scene.updateMove(of: house, snapping: true)
        let snapped = scene.endMove(of: house, snapping: true)
        #expect(snapped)

        #expect(abs(baseCenter(house).x - treeCenter) < 1e-4)
        #expect(simd_angle(house.orientation, turned) < 1e-5)
    }

    @Test func snappingOffLeavesTheObjectExactlyWhereItWasLetGo() {
        let scene = WorkspaceScene()
        let house = scene.addObject(SampleObjectCatalog.make(.house, tint: nil), name: "House")
        let tree = scene.addObject(SampleObjectCatalog.make(.tree, tint: nil), name: "Tree")
        tree.position = [0.12, 0, -0.1]
        scene.beginMove(of: house)
        house.position = [tree.position.x + 0.002, 0, 0.1]
        scene.updateMove(of: house, snapping: false)
        let letGo = house.position
        let snapped = scene.endMove(of: house, snapping: false)
        #expect(!snapped)
        #expect(house.position == letGo)
    }

    @Test func tiltRingTiltsForwardAboutTheCenterWithoutTurning() {
        let (scene, object) = sceneWithSelectedHouse()
        let center = WorkspaceScene.center(of: object)
        let handle = Entity()
        handle.components.set(SelectionHandleComponent(kind: .tilt))

        // Start at the top of the arc, then drag forward (+Z, toward the object's front) and
        // down by 30° around the center.
        let radius: Float = 0.1
        #expect(scene.dragHandle(handle, to: center + [0, radius, 0], snapping: false) === object)
        let angle: Float = .pi / 6
        scene.dragHandle(handle, to: center + [0, radius * cos(angle), radius * sin(angle)], snapping: false)
        scene.endHandleDrag()

        // Leaned forward 30°: up now points partly toward +Z.
        let up = object.orientation.act([0, 1, 0])
        #expect(abs(atan2(up.z, up.y) - angle) < 0.001)
        // Still facing the same way: its side-to-side axis didn't move.
        let side = object.orientation.act([1, 0, 0])
        #expect(simd_distance(side, [1, 0, 0]) < 1e-4)
        // It pivoted about its own center.
        #expect(simd_distance(WorkspaceScene.center(of: object), center) < 1e-4)
    }

    @Test func tiltRingDetentsLevelTheObject() {
        let (scene, object) = sceneWithSelectedHouse()
        let center = WorkspaceScene.center(of: object)
        let handle = Entity()
        handle.components.set(SelectionHandleComponent(kind: .tilt))
        scene.dragHandle(handle, to: center + [0, 0.1, 0], snapping: true)
        // 2° forward is within the detent: stays upright.
        let small: Float = 2 * .pi / 180
        scene.dragHandle(handle, to: center + [0, 0.1 * cos(small), 0.1 * sin(small)], snapping: true)
        scene.endHandleDrag()
        #expect(simd_distance(object.orientation.act([0, 1, 0]), [0, 1, 0]) < 1e-5)
    }

    @Test func turnRingTurnsInPlaceAfterTheBaseIsSpun() {
        let (scene, object) = sceneWithSelectedHouse()
        scene.setBaseSpin(0.9)
        object.position = [0.05, 0, 0.02]
        scene.handles.root.position = object.position(relativeTo: nil)
        let center = WorkspaceScene.center(of: object)
        let before = object.orientation
        let handle = Entity()
        handle.components.set(SelectionHandleComponent(kind: .rotate))

        let pivot = scene.handles.pivot
        scene.dragHandle(handle, to: pivot + [0.1, 0, 0], snapping: false)
        let angle: Float = 0.6
        scene.dragHandle(handle, to: pivot + [0.1 * cos(angle), 0, -0.1 * sin(angle)], snapping: false)
        scene.endHandleDrag()

        // Turned by exactly the drag, about vertical, in place.
        #expect(abs(simd_angle(object.orientation, before) - angle) < 0.001)
        #expect(simd_distance(object.orientation.act([0, 1, 0]), [0, 1, 0]) < 1e-5)
        #expect(simd_distance(WorkspaceScene.center(of: object), center) < 1e-4)
    }

    @Test func tiltAfterSpinningTheBaseStaysAboutTheObjectsOwnAxis() {
        let (scene, object) = sceneWithSelectedHouse()
        scene.setBaseSpin(1.1)
        object.orientation = simd_quatf(angle: 0.4, axis: [0, 1, 0])
        // Line the handles up with the object as the follow system would.
        let worldX = object.convert(direction: [1, 0, 0], to: nil)
        scene.handles.root.orientation = simd_quatf(angle: atan2(-worldX.z, worldX.x), axis: [0, 1, 0])
        let sideBefore = object.convert(direction: [1, 0, 0], to: nil)
        let center = WorkspaceScene.center(of: object)
        let handle = Entity()
        handle.components.set(SelectionHandleComponent(kind: .tilt))
        let forward = simd_cross([0, 1, 0], scene.handles.tiltAxis)

        scene.dragHandle(handle, to: center + [0, 0.1, 0], snapping: false)
        scene.dragHandle(handle, to: center + 0.1 * (forward * sin(0.4) + [0, cos(0.4), 0]), snapping: false)
        scene.endHandleDrag()

        // Tilting never turns the object: its side axis is unchanged in the world.
        let sideAfter = object.convert(direction: [1, 0, 0], to: nil)
        #expect(simd_distance(sideAfter, sideBefore) < 1e-4)
        #expect(simd_length(object.convert(direction: [0, 1, 0], to: nil) - [0, 1, 0]) > 0.1)
    }

    private func simd_angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
        let dot = min(abs(simd_dot(a.vector, b.vector)), 1)
        return 2 * acos(dot)
    }

    // MARK: Backdrop preference

    private func makeDefaults() -> UserDefaults {
        let name = "InteractionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func backdropPreferenceIsRememberedAcrossLaunches() {
        let defaults = makeDefaults()
        let first = BackdropVisibilityController(defaults: defaults)
        #expect(first.preference == .alwaysShow)
        first.preference = .hideBetweenPhotos

        // A new launch reads it back immediately, already hidden.
        let relaunched = BackdropVisibilityController(defaults: defaults)
        #expect(relaunched.preference == .hideBetweenPhotos)
        #expect(!relaunched.isVisible)
    }

    @Test func aPhotoShowsTheBackdropThenHidesItWithoutChangingThePreference() {
        let defaults = makeDefaults()
        let backdrop = BackdropVisibilityController(defaults: defaults)
        backdrop.preference = .hideBetweenPhotos

        backdrop.photoStarted()
        #expect(backdrop.isVisible && backdrop.isShownForPhoto)
        backdrop.photoTaken()
        #expect(!backdrop.isVisible)
        #expect(BackdropVisibilityController(defaults: defaults).preference == .hideBetweenPhotos)
    }

    @Test func aFailedPhotoKeepsTheBackdropUpForARetry() {
        let backdrop = BackdropVisibilityController(defaults: makeDefaults())
        backdrop.preference = .hideBetweenPhotos
        backdrop.photoStarted()
        backdrop.photoFailed()
        #expect(backdrop.isVisible)
        // Leaving the camera puts it away.
        backdrop.photoWorkflowEnded()
        #expect(!backdrop.isVisible)
    }

    @Test func alwaysShowIsNeverHiddenByAPhoto() {
        let backdrop = BackdropVisibilityController(defaults: makeDefaults())
        backdrop.photoStarted()
        backdrop.photoTaken()
        backdrop.photoWorkflowEnded()
        #expect(backdrop.isVisible)
        #expect(!backdrop.isShownForPhoto)
    }

    @Test func hiddenBackdropIsStillUsedForPhotos() async throws {
        let scene = WorkspaceScene()
        scene.setBackdropShown(false, animated: false)
        let context = CGContext(data: nil, width: 32, height: 18, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        try await scene.setBackdropImage(try #require(context.makeImage()))
        // Enabled (so captures frame against it), but faded out of the room.
        #expect(scene.backdrop.isEnabled)
        #expect(scene.backdrop.components[OpacityComponent.self]?.opacity == 0)
        scene.setBackdropShown(true, animated: false)
        #expect(scene.backdrop.components[OpacityComponent.self]?.opacity == 1)
    }
}

extension SharedStateTests {
    /// The backdrop preference through the app, which keeps it in the standard defaults.
    @MainActor
    @Suite(.serialized)
    struct BackdropVisibilityAppTests {
        @Test func hideBetweenPhotosAppliesAtLaunchAndSurvivesAPhotoSession() async throws {
            let key = BackdropVisibilityController.defaultsKey
            let saved = UserDefaults.standard.object(forKey: key)
            defer { UserDefaults.standard.set(saved, forKey: key) }
            UserDefaults.standard.set(BackdropVisibility.hideBetweenPhotos.rawValue, forKey: key)

            let storage = FileManager.default.temporaryDirectory.appending(path: "BackdropVisibility-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            ProjectStore.storageOverride = storage

            // Hidden from the very first frame, before any image is loaded.
            let app = AppModel()
            #expect(!app.workspace.isBackdropShown)

            app.selectedTab = .photos
            app.showBackdropForFraming()
            #expect(app.workspace.isBackdropShown)
            #expect(app.isBackdropShownForPhoto)

            // Leaving the camera hides it again, and the preference is untouched.
            app.selectedTab = .objects
            #expect(!app.workspace.isBackdropShown)
            #expect(app.backdropVisibilityPreference == .hideBetweenPhotos)
            #expect(UserDefaults.standard.string(forKey: key) == BackdropVisibility.hideBetweenPhotos.rawValue)

            // Cancelling a countdown keeps it up for a retry.
            app.selectedTab = .photos
            app.showBackdropForFraming()
            app.cancelCapture()
            #expect(app.workspace.isBackdropShown)
            app.hideBackdropForNow()
            #expect(!app.workspace.isBackdropShown)

            app.backdropVisibilityPreference = .alwaysShow
            #expect(app.workspace.isBackdropShown)
        }
    }
}
