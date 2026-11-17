//
//  PoseEditor.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit
import simd

/// Poses characters: joint angles, hands and feet reached by inverse kinematics, dragging body
/// parts in the Pose Studio, and the library of saved poses. Keeps body parts from passing
/// through each other and holds the Pose Studio's large copy of the character.
///
/// `AppModel` owns one and hands it the character entity to change. It decides which character
/// is selected and wraps each edit in undo and saving, so this type never reaches back into the
/// project or the undo history. Edits that change a pose return true, so the caller knows to
/// treat the project as changed.
@MainActor
@Observable
final class PoseEditor {
    private let workspace: WorkspaceScene

    init(workspace: WorkspaceScene) {
        self.workspace = workspace
    }

    /// The body part selected in the Pose Studio.
    private(set) var selectedJoint: Joint?

    func selectJoint(_ joint: Joint?) {
        selectedJoint = joint
    }

    /// Bumped on every pose change, so views reading the scene refresh.
    private(set) var revision = 0

    /// Call after changing a character's pose or body outside this editor (rebuilding it,
    /// or restoring a snapshot), so views refresh.
    func poseChanged() {
        revision &+= 1
    }

    func pose(of object: Entity) -> CharacterPose? {
        workspace.characterPose(of: object)
    }

    /// Replaces a character's pose, live. `grounded` settles it back onto its feet.
    @discardableResult
    func setPose(_ pose: CharacterPose, on object: Entity, grounded: Bool = true) -> Bool {
        workspace.setCharacterPose(pose, on: object, grounded: grounded)
        poseChanged()
        return true
    }

    // MARK: Joint angles

    /// Sets one joint angle, live. The part stops where it would sink into the body.
    @discardableResult
    func setJointAngle(_ value: Float, axis: JointAxis, of joint: Joint, on object: Entity) -> Bool {
        guard let current = pose(of: object) else { return false }
        var pose = current
        var rotation = pose[joint]
        rotation[axis] = value
        pose[joint] = rotation
        return setPose(avoidingContact(pose, from: current, on: object), on: object)
    }

    /// As much of `candidate` as the body allows without parts passing through each other.
    private func avoidingContact(_ candidate: CharacterPose, from current: CharacterPose, on object: Entity) -> CharacterPose {
        guard let layout = workspace.rigLayout(of: object) else { return candidate }
        return BodyCollision.resolve(from: current, toward: candidate, layout: layout)
    }

    // MARK: Hands and feet

    /// The limb's hand or foot position relative to its shoulder or hip, at human scale in
    /// meters: x outward from the body, y up, z forward.
    func reach(of limb: Limb, on object: Entity) -> SIMD3<Float>? {
        guard let pose = pose(of: object), let layout = workspace.rigLayout(of: object) else { return nil }
        var point = LimbIK.effector(of: limb, in: pose, layout: layout)
        point.x *= limb.outward
        return point
    }

    func bendDirection(of limb: Limb, on object: Entity) -> Float? {
        guard let pose = pose(of: object), let layout = workspace.rigLayout(of: object) else { return nil }
        return LimbIK.bendDirection(of: limb, in: pose, layout: layout)
    }

    /// Moves the hand or foot to `reach` (as from `reach(of:on:)`), live.
    @discardableResult
    func setReach(_ reach: SIMD3<Float>, of limb: Limb, on object: Entity) -> Bool {
        var target = reach
        target.x *= limb.outward
        return solveReach(limb, target: target, bendDirection: bendDirection(of: limb, on: object) ?? 0,
                          grounded: true, on: object)
    }

    /// Turns the elbow or knee around the line to the hand or foot, live.
    @discardableResult
    func setBendDirection(_ degrees: Float, of limb: Limb, on object: Entity) -> Bool {
        guard let pose = pose(of: object), let layout = workspace.rigLayout(of: object) else { return false }
        return solveReach(limb, target: LimbIK.effector(of: limb, in: pose, layout: layout), bendDirection: degrees,
                          grounded: true, on: object)
    }

    private func solveReach(_ limb: Limb, target: SIMD3<Float>, bendDirection: Float, grounded: Bool, on object: Entity) -> Bool {
        guard let pose = pose(of: object), let layout = workspace.rigLayout(of: object) else { return false }
        let solved = LimbIK.solve(limb, reaching: target, bendDirection: bendDirection, pose: pose, layout: layout)
        return setPose(avoidingContact(solved, from: pose, on: object), on: object, grounded: grounded)
    }

    // MARK: Dragging body parts (Pose Studio)

    /// True while a body part is being dragged. The body doesn't re-settle onto its feet
    /// until the drag ends, so it doesn't shift under the hand.
    private(set) var isDragging = false

    /// How the dragged part started, so each drag is relative to where it began.
    private enum DragStart {
        case swing(Joint, JointRotation)
        case hand(Limb, SIMD3<Float>)
    }
    @ObservationIgnored private var dragStart: DragStart?
    /// The drag point, eased toward the hand's actual position to take out jitter.
    @ObservationIgnored private var smoothedDragPoint: SIMD3<Float>?

    /// Eases a drag point: follows the hand closely, without its tremor.
    private func smoothed(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let eased = smoothedDragPoint.map { $0 + (point - $0) * 0.55 } ?? point
        smoothedDragPoint = eased
        return eased
    }

    /// Marks a drag as started; `beginning` runs once per drag, before anything changes.
    private func beginDrag(_ beginning: () -> Void) {
        if !isDragging {
            isDragging = true
            beginning()
        }
    }

    /// Swings a joint to follow a drag: `from` and `to` are the drag's start and current
    /// directions from the joint, in its parent's space. The part stops at the body's
    /// surface instead of passing into it. `beginning` runs when the drag starts, before the
    /// pose changes. End with `endDrag(on:)`.
    @discardableResult
    func swingJoint(_ joint: Joint, from: SIMD3<Float>, to: SIMD3<Float>, on object: Entity,
                    beginning: () -> Void) -> Bool {
        guard let current = pose(of: object), let layout = workspace.rigLayout(of: object) else { return false }
        if case .swing(let started, _) = dragStart, started == joint {} else {
            beginDrag(beginning)
            dragStart = .swing(joint, current[joint])
            smoothedDragPoint = nil
            selectJoint(joint)
        }
        guard case .swing(_, let start) = dragStart else { return false }
        var from = from, to = smoothed(to)
        // A grab right at the joint (on its ball) would make tiny hand movements spin the part.
        // Measure from along the part instead, so it turns as if pulled by its far end.
        let lever = CharacterKinematics.rotation(start, for: joint).act(Self.lever(of: joint, layout: layout))
        if simd_length(from) < simd_length(lever) * 0.6 {
            from += lever
            to += lever
        }
        var pose = current
        pose[joint] = CharacterKinematics.swing(joint, startingAt: start, from: from, to: to)
        return setPose(avoidingContact(pose, from: current, on: object), on: object, grounded: false)
    }

    /// A body part's length and direction from its joint, at rest: what it's pulled by.
    private static func lever(of joint: Joint, layout: RigLayout) -> SIMD3<Float> {
        switch joint {
        case .pelvis: [0, 0.3, 0]
        case .spine: [0, 0.2, 0]
        case .chest: [0, 0.25, 0]
        case .neck: [0, 0.12, 0]
        case .head: [0, 0.2 * layout.proportions.head, 0]
        case .leftShoulder, .rightShoulder: layout.offset(of: .leftElbow)
        case .leftElbow, .rightElbow: layout.offset(of: .leftWrist)
        case .leftWrist, .rightWrist: [0, -0.16, 0]
        case .leftHip, .rightHip: layout.offset(of: .leftKnee)
        case .leftKnee, .rightKnee: layout.offset(of: .leftAnkle)
        case .leftAnkle, .rightAnkle: [0, -0.04, 0.18]
        }
    }

    /// Moves a hand or foot with a drag, bending the arm or leg to follow: `from` and `to`
    /// are the drag's start and current points relative to the shoulder or hip, in the
    /// solver's space. `beginning` runs when the drag starts. End with `endDrag(on:)`.
    @discardableResult
    func dragHand(_ limb: Limb, from: SIMD3<Float>, to: SIMD3<Float>, on object: Entity,
                  beginning: () -> Void) -> Bool {
        guard let pose = pose(of: object), let layout = workspace.rigLayout(of: object) else { return false }
        if case .hand(let started, _) = dragStart, started == limb {} else {
            beginDrag(beginning)
            dragStart = .hand(limb, LimbIK.effector(of: limb, in: pose, layout: layout))
            smoothedDragPoint = nil
            selectJoint(limb.end)
        }
        guard case .hand(_, let start) = dragStart else { return false }
        let bend = LimbIK.bendDirection(of: limb, in: pose, layout: layout)
        return solveReach(limb, target: start + (smoothed(to) - from), bendDirection: bend, grounded: false, on: object)
    }

    /// Finishes a drag: the body settles back onto its feet. Returns false if no drag was
    /// under way.
    @discardableResult
    func endDrag(on object: Entity?) -> Bool {
        guard isDragging else { return false }
        isDragging = false
        dragStart = nil
        smoothedDragPoint = nil
        if let object, let pose = pose(of: object) {
            setPose(pose, on: object)
        }
        return true
    }

    // MARK: Looking at things

    /// What each character was last turned to look at, for aiming again after things move.
    /// Not saved: the pose itself is.
    private(set) var lookTargets: [ObjectID: ObjectID] = [:]

    /// Turns the character's head (with its neck and chest) to face `point`, a position in
    /// the room. Returns false if nothing changed.
    @discardableResult
    func look(at point: SIMD3<Float>, target: ObjectID, on object: Entity, id: ObjectID) -> Bool {
        lookTargets[id] = target
        guard let current = pose(of: object), let layout = workspace.rigLayout(of: object),
              let target = rigPoint(point, of: object, layout: layout) else { return false }
        let aimed = HeadAim.aim(current, at: target, layout: layout)
        guard !aimed.matches(current, tolerance: 0.01) else { return false }
        return setPose(aimed, on: object)
    }

    func forgetLookTarget(of id: ObjectID) {
        lookTargets[id] = nil
    }

    /// How far (degrees) the character's face points from `point`: how close it came.
    func lookError(at point: SIMD3<Float>, on object: Entity) -> Float? {
        guard let current = pose(of: object), let layout = workspace.rigLayout(of: object),
              let target = rigPoint(point, of: object, layout: layout) else { return nil }
        return HeadAim.angleOff(current, from: target, layout: layout)
    }

    /// A point in the room in the rig's own space (human scale, before grounding shifts the body).
    private func rigPoint(_ point: SIMD3<Float>, of object: Entity, layout: RigLayout) -> SIMD3<Float>? {
        guard let rig = CharacterBuilder.rig(in: object), let pelvis = CharacterBuilder.joints(in: rig)[.pelvis],
              let space = pelvis.parent else { return nil }
        return space.convert(position: point, from: nil) - (pelvis.position - layout.offset(of: .pelvis))
    }

    // MARK: Sitting

    enum SitResult: Equatable {
        case seated
        /// The seat is higher than the legs reach; the feet stay on the ground, so the hips
        /// end up lower than the seat's top.
        case seatTooHigh
    }

    /// Sits the character on top of `seat`, an object in the same container: hips just above
    /// its top, thighs over it, feet on the ground in front. Keeps the character's facing.
    func sit(_ object: Entity, on seat: Entity, sittingPose: CharacterPose) -> SitResult? {
        guard let layout = workspace.rigLayout(of: object), let container = object.parent,
              let rig = CharacterBuilder.rig(in: object), let pelvis = CharacterBuilder.joints(in: rig)[.pelvis],
              let space = pelvis.parent,
              let seatBounds = Self.bounds(of: seat, in: container)
        else { return nil }

        // Seat height above the ground the character stands on, at human scale.
        let ground = object.position.y
        let scale = max(space.scale(relativeTo: container).x, 1e-6)
        let seatHeight = (seatBounds.max.y - ground) / scale
        let tooHigh = seatHeight > SeatedLegs.highestSeat(layout: layout)
        setPose(SeatedLegs.sit(sittingPose, seatHeight: max(seatHeight, 0.15), layout: layout), on: object)

        // Slide over the seat: hips a little behind its middle, so the thighs rest along it.
        let hips = space.convert(position: pelvis.position, to: container)
        var forward = space.convert(direction: [0, 0, 1], to: container)
        forward.y = 0
        forward = simd_length(forward) > 1e-5 ? simd_normalize(forward) : [0, 0, 1]
        let wanted = SIMD3(seatBounds.center.x, 0, seatBounds.center.z) - forward * (layout.thigh * 0.35 * scale)
        object.position.x += wanted.x - hips.x
        object.position.z += wanted.z - hips.z
        poseChanged()
        return tooHigh ? .seatTooHigh : .seated
    }

    /// An object's geometry bounds in another entity's space.
    private static func bounds(of entity: Entity, in space: Entity) -> BoundingBox? {
        guard let local = WorkspaceScene.geometryBounds(of: entity) else { return nil }
        var result: BoundingBox?
        for corner in 0..<8 {
            let point = SIMD3(corner & 1 == 0 ? local.min.x : local.max.x,
                              corner & 2 == 0 ? local.min.y : local.max.y,
                              corner & 4 == 0 ? local.min.z : local.max.z)
            let converted = entity.convert(position: point, to: space)
            result = result.map { $0.union(converted) } ?? BoundingBox(min: converted, max: converted)
        }
        return result
    }

    // MARK: Saved poses

    /// Poses saved for reuse, shared by every project.
    private(set) var savedPoses: [SavedPose] = PoseLibraryStore.load()
    private(set) var libraryError: String?

    /// Saves a pose for reuse in any project. A pose with the same name is replaced.
    func savePose(_ pose: CharacterPose, named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var poses = savedPoses
        if let index = poses.firstIndex(where: { $0.name == name }) {
            poses[index].pose = pose
        } else {
            poses.append(SavedPose(name: name, pose: pose))
        }
        storeSavedPoses(poses)
    }

    func deleteSavedPose(_ saved: SavedPose) {
        storeSavedPoses(savedPoses.filter { $0.id != saved.id })
    }

    private func storeSavedPoses(_ poses: [SavedPose]) {
        do {
            try PoseLibraryStore.save(poses)
            savedPoses = poses
            libraryError = nil
        } catch {
            libraryError = "The pose couldn't be saved. \(error.localizedDescription)"
        }
    }

    // MARK: Pose Studio

    /// The large copy of the selected character shown in the Pose Studio window.
    let studio = PoseStudioScene()
    var isStudioOpen = false

    /// Shows `recipe`'s character in the studio in `pose`, or empties it when `recipe` is nil.
    func updateStudio(recipe: ModelRecipe?, pose: CharacterPose?) {
        studio.show(recipe: recipe, pose: pose, grounded: !isDragging, selectedJoint: selectedJoint)
    }
}
