//
//  GravityTests.swift
//  Storyboard3DWorkspaceTests
//

import RealityKit
import Testing
@testable import Storyboard3DWorkspace

/// Runs the real gravity system in an offscreen RealityKit scene.
@MainActor
struct GravityTests {
    let renderer: RealityRenderer
    let container = Entity()

    init() throws {
        ObjectGravityComponent.registerComponent()
        GravitySurfaceComponent.registerComponent()
        ObjectGravitySystem.registerSystem()
        renderer = try RealityRenderer()
        container.components.set(GravitySurfaceComponent(baseRadius: 0.3, baseHeight: 0.024))
        renderer.entities.append(container)
    }

    private func place(_ kind: SampleObjectCatalog.Kind, at position: SIMD3<Float>, tilt: Float = 0) -> Entity {
        let object = Entity()
        object.addChild(SampleObjectCatalog.make(kind, tint: nil))
        object.position = position
        object.orientation = simd_quatf(angle: tilt, axis: [0, 0, 1])
        object.components.set(ObjectGravityComponent())
        container.addChild(object)
        return object
    }

    private func bottom(_ object: Entity) -> Float { object.children[0].visualBounds(relativeTo: container).min.y }
    private func top(_ object: Entity) -> Float { object.children[0].visualBounds(relativeTo: container).max.y }

    private func settle(seconds: Double = 1) throws {
        for _ in 0..<Int(seconds * 60) { try renderer.update(1.0 / 60) }
    }

    @Test func releasedObjectsFallOntoTheBaseWithoutTipping() throws {
        let tree = place(.tree, at: [0, 0.15, 0], tilt: 0.6)
        let rotation = tree.orientation
        try settle()
        #expect(abs(bottom(tree)) < 0.0005)
        #expect(tree.orientation == rotation)
    }

    @Test func objectsBelowTheSurfaceAreLifted() throws {
        let car = place(.car, at: [0.1, -0.03, 0])
        try renderer.update(1.0 / 60)
        #expect(abs(bottom(car)) < 0.0005)
    }

    @Test func objectsPastTheEdgeLandOnTheTable() throws {
        let house = place(.house, at: [0.4, 0.1, 0])
        try settle()
        #expect(abs(bottom(house) - -0.024) < 0.0005)
    }

    @Test func objectsStackOnEachOther() throws {
        let house = place(.house, at: [0, 0, 0])
        let car = place(.car, at: [0.005, 0.25, 0])
        let tree = place(.tree, at: [0.12, 0.2, 0])
        try settle(seconds: 1.5)
        #expect(abs(bottom(car) - top(house)) < 0.0005)
        #expect(abs(bottom(tree)) < 0.0005)
    }

    @Test func heldObjectsDoNotFall() throws {
        let rock = place(.rock, at: [0, 0.1, 0])
        rock.components[ObjectGravityComponent.self]?.isHeld = true
        let height = rock.position.y
        try settle()
        #expect(rock.position.y == height)
    }
}
