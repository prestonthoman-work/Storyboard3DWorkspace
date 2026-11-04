//
//  ObjectGravity.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// Marks a placed object that falls onto the base when released.
struct ObjectGravityComponent: Component {
    /// True while the person is holding the object.
    var isHeld = false
    var fallSpeed: Float = 0
}

/// Describes the surface the objects in a container rest on. Lives on the objects container,
/// whose origin is the center of the base's top surface.
struct GravitySurfaceComponent: Component {
    /// Radius of the round base. Objects centered outside it rest on the table instead.
    var baseRadius: Float
    /// Height of the base's top above the table it sits on.
    var baseHeight: Float
}

/// Drops released objects straight down until their lowest point touches the surface
/// below them, and stops any object, held or not, from sinking beneath it.
///
/// Only position changes: rotation is never touched, so a tilted object lands tilted
/// rather than toppling. There's no stacking; everything lands on the base or table.
struct ObjectGravitySystem: System {
    static let gravity: Float = 9.8
    /// Paused during animation playback so falling doesn't fight the keyframes.
    /// Objects are still kept from sinking below the surface.
    static var isFallingPaused = false

    private static let query = EntityQuery(where: .has(ObjectGravityComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        // Cap the step so a hitch doesn't launch an object through the floor.
        let deltaTime = Float(min(context.deltaTime, 1.0 / 30))

        for object in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var gravity = object.components[ObjectGravityComponent.self],
                  let gap = Self.gapAboveSurface(of: object)
            else { continue }

            if gap < 0 {
                object.position.y -= gap
                gravity.fallSpeed = 0
            } else if !gravity.isHeld && !Self.isFallingPaused && gap > 0.0005 {
                gravity.fallSpeed += Self.gravity * deltaTime
                let drop = min(gravity.fallSpeed * deltaTime, gap)
                object.position.y -= drop
                if drop >= gap { gravity.fallSpeed = 0 }
            } else {
                gravity.fallSpeed = 0
            }
            object.components.set(gravity)
        }
    }

    /// Raises `object` if it has been pushed below the surface. Used right after each
    /// manipulation update so a held object never visibly dips under the base.
    static func keepAboveSurface(_ object: Entity) {
        guard let gap = gapAboveSurface(of: object), gap < 0 else { return }
        object.position.y -= gap
    }

    /// Distance from the object's lowest point down to the surface below it, in the
    /// container's space. Negative when the object is sunk into the surface.
    private static func gapAboveSurface(of object: Entity) -> Float? {
        guard let container = object.parent,
              let surface = container.components[GravitySurfaceComponent.self]
        else { return nil }

        // Measure only the object's geometry, not the selection ring that may be attached to it.
        let geometry = object.children.filter { $0.name != WorkspaceScene.selectionIndicatorName }
        var bounds: BoundingBox?
        for child in geometry {
            let childBounds = child.visualBounds(relativeTo: container, excludeInactive: true)
            guard !childBounds.isEmpty else { continue }
            bounds = bounds.map { $0.union(childBounds) } ?? childBounds
        }
        guard let bounds else { return nil }

        let isOverBase = simd_length(SIMD2(bounds.center.x, bounds.center.z)) <= surface.baseRadius
        let floor: Float = isOverBase ? 0 : -surface.baseHeight
        return bounds.min.y - floor
    }
}
