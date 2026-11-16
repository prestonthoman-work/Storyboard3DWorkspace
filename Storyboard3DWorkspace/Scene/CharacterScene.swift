//
//  CharacterScene.swift
//  Storyboard3DWorkspace
//

import RealityKit

/// Characters in the staged scene. In the scene a character is always one movable piece;
/// its joints are posed in the Pose Studio, and the pose lands here.
extension WorkspaceScene {
    func isCharacter(_ object: Entity) -> Bool {
        object.components.has(CharacterPoseComponent.self)
    }

    func characterPose(of object: Entity) -> CharacterPose? {
        object.components[CharacterPoseComponent.self]?.pose
    }

    func rigLayout(of object: Entity) -> RigLayout? {
        CharacterBuilder.rig(in: object)?.components[CharacterRigComponent.self].map { RigLayout(proportions: $0.proportions) }
    }

    /// Poses a placed character. Its place in the scene and size don't change, and its grab
    /// box is refitted to the new shape.
    func setCharacterPose(_ pose: CharacterPose, on object: Entity, grounded: Bool = true) {
        object.components.set(CharacterPoseComponent(pose: pose))
        guard let rig = CharacterBuilder.rig(in: object) else { return }
        CharacterBuilder.apply(pose, to: rig, grounded: grounded)
        if object.components.has(ManipulationComponent.self) { updateCollisionShape(of: object) }
    }

    /// Poses of every visible character, keyed by object.
    func currentCharacterPoses() -> [ObjectID: CharacterPose] {
        Dictionary(uniqueKeysWithValues: objects.filter(\.isEnabled).compactMap { object in
            guard let id = objectID(of: object), let pose = characterPose(of: object) else { return nil }
            return (id, pose)
        })
    }

    /// The joint entity for a joint of a placed character.
    func jointEntity(_ joint: Joint, of object: Entity) -> Entity? {
        CharacterBuilder.rig(in: object).flatMap { CharacterBuilder.joints(in: $0)[joint] }
    }
}
