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

/// Drops released objects straight down until their lowest point touches whatever is
/// beneath them, and stops any object, held or not, from sinking into it.
///
/// What's beneath can be the base, the table past the base's edge, or another object:
/// objects stack. An object counts as a support when their footprints overlap and its
/// top is below the falling object's middle. So an object released overlapping the top
/// of another settles onto it, while one released deep inside another drops through.
///
/// Only position changes: rotation is never touched, so a tilted object lands tilted
/// rather than toppling. Shapes are approximated by axis-aligned boxes.
struct ObjectGravitySystem: System {
    static let gravity: Float = 9.8
    /// Paused during animation playback so falling doesn't fight the keyframes.
    /// Objects are still kept from sinking below the surface.
    static var isFallingPaused = false
    /// Landing speed (m/s) above which an object visibly squashes and makes a sound.
    static let landingFeedbackSpeed: Float = 0.45

    private static let query = EntityQuery(where: .has(ObjectGravityComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        // Cap the step so a hitch doesn't launch an object through the floor.
        let deltaTime = Float(min(context.deltaTime, 1.0 / 30))
        let objects = Array(context.entities(matching: Self.query, updatingSystemWhen: .rendering))

        for object in objects {
            guard var gravity = object.components[ObjectGravityComponent.self],
                  let gap = Self.gapBelow(object, among: objects)
            else { continue }

            if gap < 0 {
                object.position.y -= gap
                gravity.fallSpeed = 0
            } else if !gravity.isHeld && !Self.isFallingPaused && gap > 0.0005 {
                gravity.fallSpeed += Self.gravity * deltaTime
                let drop = min(gravity.fallSpeed * deltaTime, gap)
                object.position.y -= drop
                if drop >= gap {
                    // Anything faster than a ~1 cm drop gets a squash and a thud.
                    if gravity.fallSpeed > Self.landingFeedbackSpeed {
                        SceneFeedback.landed(object, speed: gravity.fallSpeed)
                    }
                    gravity.fallSpeed = 0
                }
            } else {
                gravity.fallSpeed = 0
            }
            object.components.set(gravity)
        }
    }

    /// Raises `object` if it has been pushed into the surface or an object below it. Used
    /// right after each manipulation update so a held object never visibly dips into them.
    static func keepAboveSurface(_ object: Entity) {
        let siblings = object.parent?.children.filter {
            $0.isEnabled && $0.components.has(ObjectGravityComponent.self)
        } ?? []
        guard let gap = gapBelow(object, among: Array(siblings)), gap < 0 else { return }
        object.position.y -= gap
    }

    /// Distance from the object's lowest point down to whatever supports it, in the
    /// container's space. Negative when the object is sunk into its support.
    private static func gapBelow(_ object: Entity, among objects: [Entity]) -> Float? {
        guard let container = object.parent,
              let surface = container.components[GravitySurfaceComponent.self],
              let bounds = geometryBounds(of: object, in: container)
        else { return nil }

        let isOverBase = simd_length(SIMD2(bounds.center.x, bounds.center.z)) <= surface.baseRadius
        var floor: Float = isOverBase ? 0 : -surface.baseHeight

        for other in objects where other != object && other.parent == container {
            guard let otherBounds = geometryBounds(of: other, in: container),
                  footprintsOverlap(bounds, otherBounds),
                  otherBounds.max.y <= bounds.center.y
            else { continue }
            floor = max(floor, otherBounds.max.y)
        }
        return bounds.min.y - floor
    }

    /// Bounds of the object's geometry only, not the selection ring that may be attached to it.
    private static func geometryBounds(of object: Entity, in container: Entity) -> BoundingBox? {
        var bounds: BoundingBox?
        for child in object.children where child.name != WorkspaceScene.selectionIndicatorName {
            let childBounds = child.visualBounds(relativeTo: container, excludeInactive: true)
            guard !childBounds.isEmpty else { continue }
            bounds = bounds.map { $0.union(childBounds) } ?? childBounds
        }
        return bounds
    }

    /// Whether two boxes overlap when seen from above, ignoring a thin margin so objects
    /// that merely touch side by side don't stack on each other's edges.
    private static func footprintsOverlap(_ a: BoundingBox, _ b: BoundingBox) -> Bool {
        let margin: Float = 0.002
        return a.min.x + margin < b.max.x && a.max.x - margin > b.min.x
            && a.min.z + margin < b.max.z && a.max.z - margin > b.min.z
    }
}
