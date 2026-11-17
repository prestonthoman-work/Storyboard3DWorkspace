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

        // Where the hips will go: a little behind the seat's middle, so the thighs rest along it.
        let ground = object.position.y
        let scale = max(space.scale(relativeTo: container).x, 1e-6)
        var forward = space.convert(direction: [0, 0, 1], to: container)
        forward.y = 0
        forward = simd_length(forward) > 1e-5 ? simd_normalize(forward) : [0, 0, 1]
        let wanted = SIMD3(seatBounds.center.x, 0, seatBounds.center.z) - forward * (layout.thigh * 0.35 * scale)

        // The seat's real height under the hips and thighs (a rock is lower at its edges than
        // its box), falling back to the top of its box.
        let samples = [wanted, wanted + forward * (layout.thigh * 0.3 * scale)]
        let heights = samples.compactMap { point in
            SurfaceProbe.cast(from: [point.x, seatBounds.max.y + 0.05, point.z], direction: [0, -1, 0],
                              at: seat, in: container)?.point.y
        }
        let seatTop = heights.max() ?? seatBounds.max.y

        // Seat height above the ground the character stands on, at human scale.
        let seatHeight = (seatTop - ground) / scale
        let tooHigh = seatHeight > SeatedLegs.highestSeat(layout: layout)
        setPose(SeatedLegs.sit(sittingPose, seatHeight: max(seatHeight, 0.15), layout: layout), on: object)

        // Slide over the seat.
        let hips = space.convert(position: pelvis.position, to: container)
        object.position.x += wanted.x - hips.x
        object.position.z += wanted.z - hips.z
        poseChanged()
        return tooHigh ? .seatTooHigh : .seated
    }

    // MARK: Leaning

    enum LeanResult: Equatable {
        case leaning
        /// The hand couldn't reach from where the character stood, so it stepped closer.
        case steppedCloser
        /// The object is too low for the back or a shoulder to rest against. Nothing changed.
        case surfaceTooLow
        /// The character is standing over or inside the object, so there's no side to lean on.
        /// Nothing changed.
        case noSide
    }

    /// Leans the character on `support`, an object in the same container.
    ///
    /// Back and shoulders: the character turns that side to the object's nearest side, tilts
    /// toward it as one piece (as people lean on a wall), and slides until it touches, with
    /// its feet on the ground. Hands: the hand goes on the nearest top or side of the object
    /// and the arm bends to reach; the character turns and steps closer if it must.
    func lean(_ object: Entity, on support: Entity, with part: LeanPart) -> LeanResult? {
        guard let container = object.parent, let layout = workspace.rigLayout(of: object),
              let supportBounds = Self.bounds(of: support, in: container),
              let bodyBounds = Self.bounds(of: object, in: container)
        else { return nil }
        if let hand = part.hand {
            return leanHand(hand, of: object, on: support, bounds: supportBounds, layout: layout, container: container)
        }
        if part == .hip || part == .elbows {
            return leanOnEdge(object, on: support, bounds: supportBounds, elbows: part == .elbows,
                              layout: layout, container: container)
        }

        // A wall to lean on must reach at least the shoulders.
        let ground = object.position.y
        guard supportBounds.max.y - ground >= (bodyBounds.max.y - ground) * 0.72 else { return .surfaceTooLow }
        guard let normal = Self.nearestSide(of: supportBounds, to: object.position) else { return .noSide }

        // Turn the leaning side toward the wall. The rig faces +Z with its left side at +X.
        let up = SIMD3<Float>(0, 1, 0)
        let forward: SIMD3<Float> = switch part {
        case .back: normal
        case .leftShoulder: simd_cross(-normal, up)
        default: simd_cross(normal, up)
        }
        object.orientation = simd_quatf(from: [0, 0, 1], to: forward)

        // Tilt the whole body toward the wall from the hips, and keep the head a little more upright.
        guard var pose = pose(of: object) else { return nil }
        switch part {
        case .back:
            pose[.pelvis] = JointRotation(bend: -Self.leanAngle)
            pose[.neck] = JointRotation(bend: Self.leanAngle / 2)
        case .leftShoulder:
            pose[.pelvis] = JointRotation(side: Self.leanAngle)
            pose[.neck] = JointRotation(side: -Self.leanAngle / 2)
        default:
            pose[.pelvis] = JointRotation(side: -Self.leanAngle)
            pose[.neck] = JointRotation(side: Self.leanAngle / 2)
        }
        setPose(pose, on: object)

        // Slide against the wall, staying in front of it rather than past its corner.
        guard let leaning = Self.bounds(of: object, in: container) else { return nil }
        let axis = abs(normal.x) > 0.5 ? 0 : 2
        let lateral = 2 - axis
        let wall = normal[axis] > 0 ? supportBounds.max[axis] : supportBounds.min[axis]
        let touching = normal[axis] > 0 ? leaning.min[axis] : leaning.max[axis]
        object.position[axis] += wall - touching
        let halfWidth = (leaning.max[lateral] - leaning.min[lateral]) / 2
        let center = (leaning.max[lateral] + leaning.min[lateral]) / 2
        let low = supportBounds.min[lateral] + halfWidth * 0.5
        let high = supportBounds.max[lateral] - halfWidth * 0.5
        if low <= high {
            object.position[lateral] += min(max(center, low), high) - center
        }

        // The box's side is the farthest out the object reaches. Where its real surface is set
        // back (a rounded rock, a tapering tower), the body can come the rest of the way.
        // Only the part of the body nearest the wall can touch it first.
        let bodyPoints = SurfaceProbe.vertices(of: object, in: container) { $0.components.has(BodyPartComponent.self) }
        let reach = bodyPoints.map { simd_dot($0, -normal) }.max() ?? 0
        let front = bodyPoints.filter { simd_dot($0, -normal) > reach - 0.008 }
        let surface = SurfaceProbe.Surface(of: support, in: container)
        let gaps = stride(from: 0, to: front.count, by: max(1, front.count / 120)).compactMap {
            surface.cast(from: front[$0], direction: -normal, maxDistance: 0.3)?.distance
        }
        if let gap = gaps.min() {
            object.position -= normal * gap
        }
        poseChanged()
        return .leaning
    }

    /// Half-sits on an edge (back to the object, hips just over its top, legs braced out in
    /// front) or leans in on the elbows (facing it, hips back from the edge, forearms on top).
    private func leanOnEdge(_ object: Entity, on support: Entity, bounds: BoundingBox, elbows: Bool,
                            layout: RigLayout, container: Entity) -> LeanResult? {
        guard let rig = CharacterBuilder.rig(in: object), let pelvis = CharacterBuilder.joints(in: rig)[.pelvis],
              let space = pelvis.parent, let normal = Self.nearestSide(of: bounds, to: object.position)
        else { return .noSide }
        let scale = max(space.scale(relativeTo: container).x, 1e-6)
        let ground = object.position.y
        let axis = abs(normal.x) > 0.5 ? 0 : 2
        let edge = normal[axis] > 0 ? bounds.max[axis] : bounds.min[axis]

        // The top's real height a little in from the edge, where the hips or forearms go.
        var probePoint = object.position
        probePoint[axis] = edge - normal[axis] * min(0.1 * scale, (bounds.max[axis] - bounds.min[axis]) / 2)
        let top = SurfaceProbe.cast(from: [probePoint.x, bounds.max.y + 0.05, probePoint.z], direction: [0, -1, 0],
                                    at: support, in: container)?.point.y ?? bounds.max.y
        let height = (top - ground) / scale

        if elbows {
            // A table: between the hips and the chest.
            guard height >= 0.55, height <= 1.25 else { return .surfaceTooLow }
            object.orientation = simd_quatf(from: [0, 0, 1], to: -normal)
            guard var pose = pose(of: object) else { return nil }
            pose[.spine] = JointRotation(bend: 18)
            pose[.chest] = JointRotation(bend: 12)
            pose[.neck] = JointRotation(bend: -14)
            setPose(pose, on: object)
            // Hips a little back from the edge.
            let hips = space.convert(position: pelvis.position, to: container)
            object.position[axis] += (edge + normal[axis] * 0.22 * scale) - hips[axis]
            // Forearms on the top, hands in toward each other.
            for limb in [Limb.leftArm, .rightArm] {
                guard let shoulder = CharacterBuilder.joints(in: rig)[limb.root], let chest = shoulder.parent,
                      let current = self.pose(of: object) else { continue }
                var wrist = space.convert(position: pelvis.position, to: container)
                wrist[axis] = edge - normal[axis] * layout.forearm * 0.75 * scale
                wrist.y = top + 0.04 * scale
                let side = space.convert(direction: [limb.outward, 0, 0], to: container)
                wrist += simd_normalize(side) * 0.1 * scale
                let target = chest.convert(position: wrist, from: container) - shoulder.position
                setPose(LimbIK.solve(limb, reaching: target, bendDirection: 20, pose: current, layout: layout), on: object)
            }
        } else {
            // A table edge, car hood, or low wall: below where the hips stand, above a chair.
            guard height <= SeatedLegs.highestSeat(layout: layout) + 0.05 else { return .surfaceTooLow }
            guard height >= 0.55 else { return .surfaceTooLow }
            object.orientation = simd_quatf(from: [0, 0, 1], to: normal)
            guard let current = pose(of: object) else { return nil }
            var pose = SeatedLegs.sit(PosePreset.standing.pose, seatHeight: height, layout: layout)
            pose[.spine] = JointRotation(bend: 6)
            pose[.leftShoulder] = current[.leftShoulder]
            pose[.rightShoulder] = current[.rightShoulder]
            setPose(pose, on: object)
            // Hips just over the edge.
            let hips = space.convert(position: pelvis.position, to: container)
            object.position[axis] += (edge - normal[axis] * 0.06 * scale) - hips[axis]
        }
        poseChanged()
        return .leaning
    }

    // MARK: Holding hands

    /// Two characters hold hands: the hands nearest each other meet between them, a little in
    /// front and at the height hands hang. If they're too far apart, `other` steps closer.
    /// Returns false if either isn't a character.
    func holdHands(_ object: Entity, with other: Entity) -> Bool {
        guard let container = object.parent, other.parent === container,
              let layoutA = workspace.rigLayout(of: object), let layoutB = workspace.rigLayout(of: other),
              let rigA = CharacterBuilder.rig(in: object), let rigB = CharacterBuilder.rig(in: other),
              let spaceA = CharacterBuilder.joints(in: rigA)[.pelvis]?.parent,
              let spaceB = CharacterBuilder.joints(in: rigB)[.pelvis]?.parent
        else { return false }
        let scaleA = spaceA.scale(relativeTo: container).x, scaleB = spaceB.scale(relativeTo: container).x

        /// The arm on the side facing the other character.
        func facingArm(of rig: Entity, space: Entity, toward point: SIMD3<Float>) -> Limb {
            let left = space.convert(direction: [1, 0, 0], to: container)
            let toPoint = point - space.convert(position: .zero, to: container)
            return simd_dot(left, toPoint) >= 0 ? .leftArm : .rightArm
        }
        let limbA = facingArm(of: rigA, space: spaceA, toward: other.position)
        let limbB = facingArm(of: rigB, space: spaceB, toward: object.position)
        guard let shoulderA = CharacterBuilder.joints(in: rigA)[limbA.root],
              let shoulderB = CharacterBuilder.joints(in: rigB)[limbB.root] else { return false }

        // Close enough for both arms to reach comfortably.
        let reachA = (layoutA.upperArm + layoutA.forearm) * scaleA
        let reachB = (layoutB.upperArm + layoutB.forearm) * scaleB
        var apart = shoulderB.convert(position: .zero, to: container) - shoulderA.convert(position: .zero, to: container)
        apart.y = 0
        let comfortable = (reachA + reachB) * 0.6
        if simd_length(apart) > comfortable, simd_length(apart) > 1e-5 {
            other.position -= simd_normalize(apart) * (simd_length(apart) - comfortable)
        }

        // Meet between the shoulders, at about where hands hang, a little forward.
        let a = shoulderA.convert(position: .zero, to: container), b = shoulderB.convert(position: .zero, to: container)
        var forward = spaceA.convert(direction: [0, 0, 1], to: container) + spaceB.convert(direction: [0, 0, 1], to: container)
        forward.y = 0
        forward = simd_length(forward) > 1e-5 ? simd_normalize(forward) : .zero
        var meeting = (a + b) / 2 + forward * 0.12 * (scaleA + scaleB) / 2
        // As low as both arms reach comfortably, like hands swinging together.
        func drop(from shoulder: SIMD3<Float>, reach: Float) -> Float {
            var level = meeting - shoulder
            level.y = 0
            return sqrt(max(pow(reach * 0.92, 2) - simd_length_squared(level), 0))
        }
        meeting.y = max(a.y - drop(from: a, reach: reachA), b.y - drop(from: b, reach: reachB))

        for (entity, rig, limb, layout) in [(object, rigA, limbA, layoutA), (other, rigB, limbB, layoutB)] {
            guard let shoulder = CharacterBuilder.joints(in: rig)[limb.root], let chest = shoulder.parent,
                  let current = pose(of: entity) else { continue }
            let target = chest.convert(position: meeting, from: container) - shoulder.position
            setPose(LimbIK.solve(limb, reaching: target, bendDirection: 0, pose: current, layout: layout), on: entity)
        }
        poseChanged()
        return true
    }

    /// How far the body tilts toward what it leans on, in degrees.
    static let leanAngle: Float = 11

    private func leanHand(_ hand: Hand, of object: Entity, on support: Entity, bounds: BoundingBox, layout: RigLayout,
                          container: Entity) -> LeanResult? {
        let limb: Limb = hand == .left ? .leftArm : .rightArm
        guard let rig = CharacterBuilder.rig(in: object),
              let shoulder = CharacterBuilder.joints(in: rig)[limb.root], let chest = shoulder.parent,
              let space = CharacterBuilder.joints(in: rig)[.pelvis]?.parent
        else { return nil }
        let scale = max(space.scale(relativeTo: container).x, 1e-6)
        let armLength = (layout.upperArm + layout.forearm) * scale
        var shoulderPoint = shoulder.convert(position: .zero, to: container)
        guard var (contact, normal) = Self.nearestSurface(of: bounds, to: shoulderPoint) else { return .noSide }

        // Face the spot if it's well off to the side or behind.
        var toContact = contact - shoulderPoint
        toContact.y = 0
        var forward = space.convert(direction: [0, 0, 1], to: container)
        forward.y = 0
        if simd_length(toContact) > 1e-5, simd_length(forward) > 1e-5 {
            let angle = acos(min(max(simd_dot(simd_normalize(toContact), simd_normalize(forward)), -1), 1))
            if angle > .pi * 0.4 {
                // Both directions are level, so this only turns the character about the vertical.
                object.orientation = simd_quatf(from: simd_normalize(forward), to: simd_normalize(toContact)) * object.orientation
            }
        }

        // Onto the object's real surface: straight down onto a top, or along the reach onto a side.
        let probe = normal.y > 0.5
            ? SurfaceProbe.cast(from: contact + [0, 0.05, 0], direction: [0, -1, 0], at: support, in: container)
            : SurfaceProbe.cast(from: shoulderPoint, direction: contact - shoulderPoint, at: support, in: container)
        if let probe {
            contact = probe.point
            normal = probe.normal
        }

        // The wrist sits a hand's thickness off the surface.
        let wrist = { (contact: SIMD3<Float>) in contact + normal * (0.035 * scale) }
        shoulderPoint = shoulder.convert(position: .zero, to: container)
        var result = LeanResult.leaning
        let reach = simd_length(wrist(contact) - shoulderPoint)
        if reach > armLength * 0.92 {
            // Step closer, along the ground, until the hand comfortably reaches.
            var step = contact - shoulderPoint
            step.y = 0
            let vertical = abs(wrist(contact).y - shoulderPoint.y)
            let wantedHorizontal = sqrt(max(pow(armLength * 0.85, 2) - vertical * vertical, 0))
            let horizontal = simd_length(step)
            if horizontal > wantedHorizontal, horizontal > 1e-5 {
                object.position += step / horizontal * (horizontal - wantedHorizontal)
                result = .steppedCloser
            }
        }

        guard let current = pose(of: object) else { return nil }
        let target = chest.convert(position: wrist(contact), from: container) - shoulder.position
        let solved = LimbIK.solve(limb, reaching: target, bendDirection: 0, pose: current, layout: layout)
        setPose(avoidingContact(solved, from: current, on: object), on: object)
        return result
    }

    /// The side of a box (as seen from above) nearest to `point`, as an outward direction
    /// along x or z. A point over the box (such as a character already half-sitting on its
    /// edge) counts as being on the side it's closest to. Nil only for a point well inside.
    private static func nearestSide(of box: BoundingBox, to point: SIMD3<Float>) -> SIMD3<Float>? {
        let dx = point.x < box.min.x ? point.x - box.min.x : (point.x > box.max.x ? point.x - box.max.x : 0)
        let dz = point.z < box.min.z ? point.z - box.min.z : (point.z > box.max.z ? point.z - box.max.z : 0)
        if dx != 0 || dz != 0 {
            return abs(dx) >= abs(dz) ? [dx > 0 ? 1 : -1, 0, 0] : [0, 0, dz > 0 ? 1 : -1]
        }
        let inward: [(Float, SIMD3<Float>)] = [(point.x - box.min.x, [-1, 0, 0]), (box.max.x - point.x, [1, 0, 0]),
                                               (point.z - box.min.z, [0, 0, -1]), (box.max.z - point.z, [0, 0, 1])]
        guard let nearest = inward.min(by: { $0.0 < $1.0 }) else { return nil }
        // Deep inside (past a quarter of the way in) there's no sensible side.
        let depth = min(box.max.x - box.min.x, box.max.z - box.min.z) / 4
        return nearest.0 <= depth ? nearest.1 : nil
    }

    /// The point on a box where a hand from `point` (a shoulder) would rest, and the outward
    /// direction of that face: the top, for anything below the shoulder, as on a counter or
    /// table; otherwise the nearest side, as on a wall. Nil if the point is inside the box.
    private static func nearestSurface(of box: BoundingBox, to point: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>)? {
        let inset = (box.max - box.min) * 0.1
        if point.y > box.max.y {
            var contact = simd_clamp(point, box.min + inset, box.max - inset)
            contact.y = box.max.y
            return (contact, [0, 1, 0])
        }
        let closest = simd_clamp(point, box.min, box.max)
        let offset = point - closest
        guard simd_length(offset) > 1e-6 else { return nil }
        var axis = 0
        for candidate in 1..<3 where abs(offset[candidate]) > abs(offset[axis]) { axis = candidate }
        var normal = SIMD3<Float>.zero
        normal[axis] = offset[axis] > 0 ? 1 : -1
        // Keep the hand a little in from the edges of the face.
        var contact = simd_clamp(closest, box.min + inset, box.max - inset)
        contact[axis] = closest[axis]
        return (contact, normal)
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

/// What a character leans on an object with.
enum LeanPart: String, CaseIterable, Identifiable {
    case back, leftShoulder, rightShoulder, leftHand, rightHand, hip, elbows

    var id: String { rawValue }

    var name: String {
        switch self {
        case .back: "Back"
        case .leftShoulder: "Left Shoulder"
        case .rightShoulder: "Right Shoulder"
        case .leftHand: "Left Hand"
        case .rightHand: "Right Hand"
        case .hip: "Hip (Half-Sit on Edge)"
        case .elbows: "Elbows (on a Table)"
        }
    }

    var hand: Hand? {
        switch self {
        case .leftHand: .left
        case .rightHand: .right
        default: nil
        }
    }
}
