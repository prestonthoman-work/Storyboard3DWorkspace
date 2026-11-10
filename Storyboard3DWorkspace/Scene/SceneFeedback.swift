//
//  SceneFeedback.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// Springs an entity's scale toward `target`, overshooting a little and settling, so
/// things pop in and squash on landing instead of snapping. Removes itself once settled.
struct ScaleSpringComponent: Component {
    var target: SIMD3<Float>
    var velocity: SIMD3<Float> = .zero
    var stiffness: Float = 260
    var damping: Float = 16
}

struct ScaleSpringSystem: System {
    private static let query = EntityQuery(where: .has(ScaleSpringComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        // Cap the step so a hitch can't make the spring explode.
        let deltaTime = Float(min(context.deltaTime, 1.0 / 30))
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var spring = entity.components[ScaleSpringComponent.self] else { continue }
            let offset = spring.target - entity.scale
            spring.velocity += (offset * spring.stiffness - spring.velocity * spring.damping) * deltaTime
            let next = entity.scale + spring.velocity * deltaTime

            let isSettled = simd_reduce_max(simd_abs(spring.target - next)) < 0.0005
                && simd_reduce_max(simd_abs(spring.velocity)) < 0.01
            if isSettled {
                entity.scale = spring.target
                entity.components.remove(ScaleSpringComponent.self)
            } else {
                entity.scale = next
                entity.components.set(spring)
            }
        }
    }
}

/// Motion and sound that make edits feel physical: objects pop in, squash when they
/// land, and shrink away when deleted.
///
/// Only active while the immersive space is open. Elsewhere (such as in tests) there's
/// no running scene to animate, so changes apply instantly and nothing is left mid-animation.
enum SceneFeedback {
    static var isEnabled = false

    /// The geometry of a placed object: everything except the selection ring.
    static func content(of object: Entity) -> [Entity] {
        object.children.filter { $0.name != WorkspaceScene.selectionIndicatorName }
    }

    /// Scales `entity` from `start` times its resting size up to that size, with a springy overshoot.
    static func spring(_ entity: Entity, from start: SIMD3<Float>, stiffness: Float = 260, damping: Float = 16) {
        guard isEnabled else { return }
        let target = restingScale(of: entity)
        entity.scale = target * start
        entity.components.set(ScaleSpringComponent(target: target, stiffness: stiffness, damping: damping))
    }

    /// A newly placed or regenerated object grows up out of the base.
    static func appear(_ object: Entity) {
        guard isEnabled else { return }
        for child in content(of: object) {
            spring(child, from: SIMD3(repeating: 0.15), stiffness: 220, damping: 14)
        }
        SoundEffects.play(.place, on: object, gain: -8)
    }

    /// An object hit the surface at `speed` (m/s): squash flat and wobble back, with a thud.
    static func landed(_ object: Entity, speed: Float) {
        guard isEnabled else { return }
        let amount = min(max(speed / 3, 0.05), 0.2)
        for child in content(of: object) {
            spring(child, from: [1 + amount * 0.5, 1 - amount, 1 + amount * 0.5], stiffness: 320, damping: 13)
        }
        let loudness = Double(min(speed / 2.5, 1))
        SoundEffects.play(.land, on: object, gain: -22 + 16 * loudness)
    }

    /// Plays a quick shrink on a stand-in copy, so the real object can be removed right
    /// away (keeping undo and the model in sync) while the deletion still reads visually.
    static func vanish(_ object: Entity) {
        guard isEnabled, let parent = object.parent else { return }
        let ghost = object.clone(recursive: true)
        stripBehavior(from: ghost)
        ghost.transform = object.transform
        parent.addChild(ghost)

        var end = ghost.transform
        end.scale *= 0.01
        end.translation.y += 0.01
        ghost.move(to: end, relativeTo: parent, duration: 0.2, timingFunction: .easeIn)
        SoundEffects.play(.remove, on: ghost, gain: -10)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            ghost.removeFromParent()
        }
    }

    private static func stripBehavior(from entity: Entity) {
        entity.components.remove(ObjectGravityComponent.self)
        entity.components.remove(PlacedObjectComponent.self)
        entity.components.remove(ManipulationComponent.self)
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(HoverEffectComponent.self)
    }

    /// The scale an entity is settling toward, which differs from its current scale mid-animation.
    private static func restingScale(of entity: Entity) -> SIMD3<Float> {
        entity.components[ScaleSpringComponent.self]?.target ?? entity.scale
    }
}
