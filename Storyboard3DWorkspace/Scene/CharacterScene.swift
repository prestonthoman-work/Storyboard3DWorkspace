//
//  CharacterScene.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Marks the draggable target for placing a hand or foot directly.
struct IKHandleComponent: Component {}

/// Keeps the hand-or-foot target on the joint it controls, except while it's being dragged.
struct IKHandleFollowComponent: Component {
    var target: Entity?
    var isDragging = false
}

struct IKHandleFollowSystem: System {
    private static let query = EntityQuery(where: .has(IKHandleFollowComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let follow = entity.components[IKHandleFollowComponent.self], !follow.isDragging,
                  let target = follow.target, target.parent != nil else { continue }
            entity.position = target.position(relativeTo: entity.parent)
        }
    }
}

/// What the posing overlay shows: which character, its selected joint, and whether the
/// hand-or-foot target is out.
struct PoseOverlay: Equatable {
    var objectID: ObjectID
    var joint: Joint?
    var showsReachTarget: Bool
}

extension WorkspaceScene {
    static let ikHandleName = "ReachTarget"

    func setUpCharacterOverlay() {
        var material = UnlitMaterial(color: UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 1))
        material.blending = .transparent(opacity: 0.9)
        ikHandle.name = Self.ikHandleName
        ikHandle.model = ModelComponent(mesh: .generateSphere(radius: 0.0045), materials: [material])
        var ringMesh = MeshBuilder()
        ringMesh.addRing(innerRadius: 0.0068, outerRadius: 0.0078, segments: 40)
        if let mesh = ringMesh.makeMesh(named: "ReachRing") {
            var ringMaterial = UnlitMaterial(color: .white)
            ringMaterial.blending = .transparent(opacity: 0.8)
            let ring = ModelEntity(mesh: mesh, materials: [ringMaterial])
            ring.components.set(BillboardComponent())
            ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            ikHandle.addChild(ring)
        }
        ikHandle.components.set(IKHandleComponent())
        ikHandle.components.set(IKHandleFollowComponent())
        ikHandle.components.set(InputTargetComponent())
        // A generous target, so it's easy to pinch even though the marker is small.
        ikHandle.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.013)]))
        ikHandle.components.set(HoverEffectComponent())
        ikHandle.isEnabled = false
        root.addChild(ikHandle)
    }

    // MARK: Character state

    func isCharacter(_ object: Entity) -> Bool {
        object.components.has(CharacterPoseComponent.self)
    }

    func characterPose(of object: Entity) -> CharacterPose? {
        object.components[CharacterPoseComponent.self]?.pose
    }

    func rigLayout(of object: Entity) -> RigLayout? {
        CharacterBuilder.rig(in: object)?.components[CharacterRigComponent.self].map { RigLayout(proportions: $0.proportions) }
    }

    /// Poses a placed character. Its place in the scene and size don't change.
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

    /// The character and joint a tapped body part belongs to.
    func joint(containing entity: Entity) -> (object: Entity, joint: Joint)? {
        var current: Entity? = entity
        while let candidate = current {
            if let joint = candidate.components[BodyPartComponent.self]?.joint ?? candidate.components[JointComponent.self]?.joint,
               let object = object(containing: candidate) {
                return (object, joint)
            }
            current = candidate.parent
        }
        return nil
    }

    // MARK: Posing mode

    /// While posing, the character stops being one movable piece: its body parts become
    /// tappable for picking joints, and its move/turn/resize handles step aside.
    func setPoseEditing(_ object: Entity?) {
        guard object != poseEditingTarget else { return }
        if let previous = poseEditingTarget, previous.parent != nil {
            if let rig = CharacterBuilder.rig(in: previous) {
                CharacterBuilder.setPartsTappable(false, in: rig)
                CharacterBuilder.showMarkers(false, selected: nil, in: rig)
            }
            restoreInteraction(for: previous)
        }
        poseEditingTarget = object
        handles.setShowsTransformHandles(object == nil)
        guard let object, let rig = CharacterBuilder.rig(in: object) else { return }
        object.components.remove(ManipulationComponent.self)
        object.components.remove(InputTargetComponent.self)
        object.components.remove(HoverEffectComponent.self)
        object.components.remove(CollisionComponent.self)
        CharacterBuilder.setPartsTappable(true, in: rig)
    }

    /// Shows the joint markers and hand-or-foot target. Nil hides them (normal viewing,
    /// playback). They're never part of photos or exports either way.
    func setPoseOverlay(_ overlay: PoseOverlay?) {
        guard overlay != poseOverlay else { return }
        if let previous = poseOverlay, let object = object(withID: previous.objectID), let rig = CharacterBuilder.rig(in: object) {
            CharacterBuilder.showMarkers(false, selected: nil, in: rig)
        }
        poseOverlay = overlay
        guard let overlay, let object = object(withID: overlay.objectID), let rig = CharacterBuilder.rig(in: object) else {
            ikHandle.isEnabled = false
            return
        }
        CharacterBuilder.showMarkers(true, selected: overlay.joint, in: rig)
        if overlay.showsReachTarget, let joint = overlay.joint, let target = jointEntity(joint, of: object) {
            ikHandle.components.set(IKHandleFollowComponent(target: target, isDragging: false))
            ikHandle.position = target.position(relativeTo: root)
            ikHandle.isEnabled = true
        } else {
            ikHandle.isEnabled = false
        }
    }

    /// Moves the hand-or-foot target with a drag.
    func moveReachTarget(to point: SIMD3<Float>, isDragging: Bool) {
        var follow = ikHandle.components[IKHandleFollowComponent.self] ?? IKHandleFollowComponent()
        follow.isDragging = isDragging
        ikHandle.components.set(follow)
        if isDragging { ikHandle.position = root.convert(position: point, from: nil) }
    }

    /// Where a world-space point is relative to a limb's shoulder or hip, in the space the
    /// IK solver uses (the chest or pelvis, at human scale).
    func limbSpacePoint(_ point: SIMD3<Float>, for limb: Limb, of object: Entity) -> SIMD3<Float>? {
        guard let parentJoint = limb.root.parent, let parent = jointEntity(parentJoint, of: object),
              let root = jointEntity(limb.root, of: object) else { return nil }
        return parent.convert(position: point, from: nil) - root.position
    }
}
