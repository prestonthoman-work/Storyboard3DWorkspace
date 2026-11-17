//
//  LookTracking.swift
//  Storyboard3DWorkspace
//

import RealityKit
import simd

/// Marks a character that keeps looking at another object or character: its head, neck, and
/// chest turn to follow the target whenever either moves, including during playback.
struct LookTargetComponent: Component {
    var target: ObjectID
}

/// Keeps every tracking character's head turned toward its target.
struct LookTrackingSystem: System {
    private static let query = EntityQuery(where: .has(LookTargetComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for character in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            LookTracking.aim(character)
        }
    }
}

enum LookTracking {
    /// Turns a tracking character toward its target, if it isn't already looking at it.
    /// Returns true if its pose changed.
    @discardableResult
    static func aim(_ character: Entity) -> Bool {
        guard let target = character.components[LookTargetComponent.self]?.target,
              let targetEntity = character.parent?.children.first(where: {
                  $0.components[PlacedObjectComponent.self]?.id == target
              }),
              let point = point(of: targetEntity),
              let rig = CharacterBuilder.rig(in: character),
              let proportions = rig.components[CharacterRigComponent.self]?.proportions,
              let pelvis = CharacterBuilder.joints(in: rig)[.pelvis], let space = pelvis.parent,
              let pose = character.components[CharacterPoseComponent.self]?.pose
        else { return false }
        let layout = RigLayout(proportions: proportions)
        let rigTarget = space.convert(position: point, from: nil) - (pelvis.position - layout.offset(of: .pelvis))
        // Already facing it (within half a degree): leave it, so nothing shifts frame to frame.
        guard HeadAim.angleOff(pose, from: rigTarget, layout: layout) > 0.5 else { return false }
        let aimed = HeadAim.aim(pose, at: rigTarget, layout: layout)
        guard !aimed.matches(pose, tolerance: 0.05) else { return false }
        character.components.set(CharacterPoseComponent(pose: aimed))
        CharacterBuilder.apply(aimed, to: rig)
        return true
    }

    /// Turns every tracking character under `root`, such as right before a render.
    static func aimAll(in root: Entity) {
        if root.components.has(LookTargetComponent.self) { aim(root) }
        for child in root.children { aimAll(in: child) }
    }

    /// Where to look on an object: a character's eyes, or the middle of anything else.
    static func point(of target: Entity) -> SIMD3<Float>? {
        if let rig = CharacterBuilder.rig(in: target), let head = CharacterBuilder.joints(in: rig)[.head],
           let proportions = rig.components[CharacterRigComponent.self]?.proportions {
            return head.convert(position: HeadAim.eyeOffset(layout: RigLayout(proportions: proportions)), to: nil)
        }
        return WorkspaceScene.geometryBounds(of: target).map { target.convert(position: $0.center, to: nil) }
    }
}
