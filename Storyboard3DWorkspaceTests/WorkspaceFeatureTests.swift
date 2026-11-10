//
//  WorkspaceFeatureTests.swift
//  Storyboard3DWorkspaceTests
//

import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

/// Shot reordering, diorama bases, the object library, and selection handles.
@MainActor
@Suite(.serialized)
struct WorkspaceFeatureTests {
    init() throws {
        let storage = FileManager.default.temporaryDirectory.appending(path: "WorkspaceFeatureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        ProjectStore.storageOverride = storage
    }

    @Test func movingAKeyframeReordersAndRetimes() {
        var timeline = KeyframeTimeline()
        let a = timeline.append([:]), b = timeline.append([:]), c = timeline.append([:])
        timeline.move(c.id, to: 0)
        #expect(timeline.keyframes.map(\.id) == [c.id, a.id, b.id])
        #expect(timeline.keyframes.map(\.time) == [0, 1, 2])
    }

    @Test func reorderingShotsCanBeUndone() async throws {
        let app = AppModel()
        await app.createProject()
        app.addKeyframe()
        app.addKeyframe()
        let original = app.animator.timeline.keyframes.map(\.id)

        app.moveKeyframe(original[1], to: 0)
        #expect(app.animator.timeline.keyframes.map(\.id) == [original[1], original[0]])

        app.undo()
        #expect(app.animator.timeline.keyframes.map(\.id) == original)
    }

    @Test(arguments: BaseTemplate.allCases)
    func objectsStandOnTheBaseSurfaceNotOnItsDetails(template: BaseTemplate) {
        let scene = WorkspaceScene()
        let size: Float = 0.6
        scene.setBase(BaseTemplateBuilder.make(template), size: size)
        // Templates are 1 m across with their walkable surface 4 cm up.
        #expect(abs(scene.objectsContainer.position.y - 0.04 * size) < 0.0005)
    }

    @Test func basesBuildTheSameEveryTime() {
        let first = BaseTemplateBuilder.make(.grass).visualBounds(relativeTo: nil)
        let second = BaseTemplateBuilder.make(.grass).visualBounds(relativeTo: nil)
        #expect(first.min == second.min && first.max == second.max)
    }

    @Test func libraryCardsPlaceTheirObject() async throws {
        let app = AppModel()
        await app.createProject()
        app.placeCatalogObject(.lamp)
        let summary = try #require(app.selectedObject)
        #expect(summary.recipe == .sampleObject(kind: "lamp", color: nil))
        #expect(app.workspace.object(withID: summary.id) != nil)
        app.undo()
        #expect(app.objects.isEmpty)
    }

    @Test(arguments: SampleObjectCatalog.Kind.allCases)
    func catalogObjectsRestOnTheGround(kind: SampleObjectCatalog.Kind) {
        let bounds = SampleObjectCatalog.make(kind, tint: nil).visualBounds(relativeTo: nil)
        #expect(abs(bounds.min.y) < 0.0005)
    }

    @Test func rotateHandleTurnsTheObjectInSnappedSteps() {
        let scene = WorkspaceScene()
        let object = scene.addObject(SampleObjectCatalog.make(.house, tint: nil), name: "House")
        scene.showSelection(on: object)
        // The follow system isn't running here, so put the handles at the object by hand.
        scene.handles.root.position = object.position(relativeTo: nil)
        let pivot = scene.handles.pivot
        let handle = Entity()
        handle.components.set(SelectionHandleComponent(kind: .rotate))

        #expect(scene.dragHandle(handle, to: pivot + [0.1, 0, 0], snapping: true) === object)
        // A quarter turn counterclockwise seen from above, nudged off the 15° grid.
        let nudge: Float = 0.05
        scene.dragHandle(handle, to: pivot + [0.1 * sin(nudge), 0, -0.1 * cos(nudge)], snapping: true)
        scene.endHandleDrag()

        let x = object.orientation.act([1, 0, 0])
        #expect(abs(atan2(-x.z, x.x) - .pi / 2) < 0.001)
    }

    @Test func scaleHandleResizesWithinLimits() {
        let scene = WorkspaceScene()
        let object = scene.addObject(SampleObjectCatalog.make(.tree, tint: nil), name: "Tree")
        scene.showSelection(on: object)
        scene.handles.root.position = object.position(relativeTo: nil)
        let pivot = scene.handles.pivot
        let handle = Entity()
        handle.components.set(SelectionHandleComponent(kind: .scale))

        scene.dragHandle(handle, to: pivot + [0.05, 0.05, 0], snapping: false)
        scene.dragHandle(handle, to: pivot + [0.1, 0.1, 0], snapping: false)
        #expect(abs(object.scale.x - 2) < 0.001)

        scene.dragHandle(handle, to: pivot + [0, 0.0000001, 0], snapping: false)
        #expect(object.scale.x == WorkspaceScene.scaleRange.lowerBound)
        scene.endHandleDrag()
    }

    // MARK: Turntable

    /// Drags around the base's center in small steps, sweeping `radians` counterclockwise from above.
    private func spin(_ scene: WorkspaceScene, by radians: Float, steps: Int = 24) {
        let center = scene.baseAnchor.position(relativeTo: nil)
        for step in 0...steps {
            let angle = radians * Float(step) / Float(steps)
            scene.dragTurntable(to: center + [0.3 * cos(angle), 0, -0.3 * sin(angle)])
        }
        scene.endTurntableDrag()
    }

    @Test func swipingTheEdgeSpinsTheWholeSetAFullTurnAndMore() {
        let scene = WorkspaceScene()
        let object = scene.addObject(SampleObjectCatalog.make(.car, tint: nil), name: "Car")
        object.position = [0.1, 0, 0]
        let localBefore = object.transform

        spin(scene, by: .pi / 2)
        #expect(abs(scene.baseSpin - .pi / 2) < 0.001)
        // The object rides along: same pose on the base, new place in the room.
        #expect(object.transform == localBefore)
        let world = object.position(relativeTo: scene.baseAnchor)
        #expect(abs(world.x) < 0.001 && abs(world.z + 0.1) < 0.001)

        spin(scene, by: 2 * .pi)
        #expect(abs(scene.baseSpin - (.pi / 2 + 2 * .pi)) < 0.001)
        #expect(scene.isSettled)
    }

    @Test func baseSpinIsSavedAndUndoable() async throws {
        let app = AppModel()
        await app.createProject()
        app.dragTurntable(to: app.workspace.baseAnchor.position(relativeTo: nil) + [0.3, 0, 0])
        for step in 1...10 {
            let angle = Float(step) / 10 * .pi / 3
            app.dragTurntable(to: app.workspace.baseAnchor.position(relativeTo: nil) + [0.3 * cos(angle), 0, -0.3 * sin(angle)])
        }
        app.workspace.endTurntableDrag()
        #expect(abs(app.currentState().base.spinRadians! - .pi / 3) < 0.001)

        app.undo()
        #expect(app.workspace.baseSpin == 0)
        app.redo()
        #expect(abs(app.workspace.baseSpin - .pi / 3) < 0.001)
    }
}
