//
//  CharacterRig.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

// MARK: Joints

/// One joint of the built-in mannequin's rig. Each joint rotates the body segment that
/// hangs from it, and everything further down the chain follows: turning a shoulder
/// carries the elbow, forearm, and hand with it.
///
/// Cases are listed parents first, so iterating `allCases` always visits a joint's parent
/// before the joint itself.
enum Joint: String, CaseIterable, Codable, CodingKeyRepresentable, Identifiable {
    case pelvis, spine, chest, neck, head
    case leftShoulder, leftElbow, leftWrist
    case rightShoulder, rightElbow, rightWrist
    case leftHip, leftKnee, leftAnkle
    case rightHip, rightKnee, rightAnkle

    var id: String { rawValue }

    var parent: Joint? {
        switch self {
        case .pelvis: nil
        case .spine: .pelvis
        case .chest: .spine
        case .neck: .chest
        case .head: .neck
        case .leftShoulder, .rightShoulder: .chest
        case .leftElbow: .leftShoulder
        case .rightElbow: .rightShoulder
        case .leftWrist: .leftElbow
        case .rightWrist: .rightElbow
        case .leftHip, .rightHip: .pelvis
        case .leftKnee: .leftHip
        case .rightKnee: .rightHip
        case .leftAnkle: .leftKnee
        case .rightAnkle: .rightKnee
        }
    }

    /// The name people see. Joints are named for the body part they move.
    var displayName: String {
        switch self {
        case .pelvis: "Hips"
        case .spine: "Waist"
        case .chest: "Chest"
        case .neck: "Neck"
        case .head: "Head"
        case .leftShoulder: "Left Shoulder"
        case .leftElbow: "Left Elbow"
        case .leftWrist: "Left Hand"
        case .rightShoulder: "Right Shoulder"
        case .rightElbow: "Right Elbow"
        case .rightWrist: "Right Hand"
        case .leftHip: "Left Hip"
        case .leftKnee: "Left Knee"
        case .leftAnkle: "Left Foot"
        case .rightHip: "Right Hip"
        case .rightKnee: "Right Knee"
        case .rightAnkle: "Right Foot"
        }
    }

    enum Region: String, CaseIterable, Identifiable {
        case body, leftArm, rightArm, leftLeg, rightLeg
        var id: String { rawValue }
        var title: String {
            switch self {
            case .body: "Head & Body"
            case .leftArm: "Left Arm"
            case .rightArm: "Right Arm"
            case .leftLeg: "Left Leg"
            case .rightLeg: "Right Leg"
            }
        }
        var joints: [Joint] { Joint.allCases.filter { $0.region == self } }
    }

    var region: Region {
        switch self {
        case .pelvis, .spine, .chest, .neck, .head: .body
        case .leftShoulder, .leftElbow, .leftWrist: .leftArm
        case .rightShoulder, .rightElbow, .rightWrist: .rightArm
        case .leftHip, .leftKnee, .leftAnkle: .leftLeg
        case .rightHip, .rightKnee, .rightAnkle: .rightLeg
        }
    }

    private var isLeft: Bool {
        [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle].contains(self)
    }

    /// The same joint on the other side of the body (itself, on the center line).
    var mirror: Joint {
        let raw = rawValue
        if raw.hasPrefix("left") { return Joint(rawValue: "right" + raw.dropFirst(4)) ?? self }
        if raw.hasPrefix("right") { return Joint(rawValue: "left" + raw.dropFirst(5)) ?? self }
        return self
    }

    /// Which way a positive angle turns, about the joint's X (bend), Y (twist), and Z (side)
    /// axes. Chosen so the same number means the same thing on both sides of the body: a
    /// positive shoulder bend raises either arm forward, a positive side raise lifts either
    /// arm away from the body.
    ///
    /// The mannequin faces +Z with +Y up, so its left is +X.
    var signs: SIMD3<Float> {
        let mirror: Float = isLeft ? 1 : -1
        switch self {
        case .pelvis, .spine, .chest, .neck, .head:
            // Bend leans forward, twist turns to the left, side tilts to the left.
            return [1, 1, -1]
        case .leftShoulder, .rightShoulder, .leftHip, .rightHip:
            // Bend raises the limb forward, twist rotates it inward, side lifts it outward.
            return [-1, -mirror, mirror]
        case .leftElbow, .rightElbow:
            return [-1, 0, 0]
        case .leftKnee, .rightKnee:
            return [1, 0, 0]
        case .leftWrist, .rightWrist:
            return [-1, -mirror, mirror]
        case .leftAnkle, .rightAnkle:
            // Bend lifts the toes, side rolls the foot outward.
            return [-1, 0, mirror]
        }
    }

    /// How far each axis may turn, in degrees, so poses stay humanly possible.
    var limits: JointLimits {
        switch self {
        case .pelvis: JointLimits(bend: -30...60, twist: -60...60, side: -25...25)
        case .spine: JointLimits(bend: -25...45, twist: -35...35, side: -25...25)
        case .chest: JointLimits(bend: -20...35, twist: -35...35, side: -20...20)
        case .neck: JointLimits(bend: -35...45, twist: -60...60, side: -30...30)
        case .head: JointLimits(bend: -30...35, twist: -45...45, side: -25...25)
        case .leftShoulder, .rightShoulder: JointLimits(bend: -60...180, twist: -90...90, side: -20...180)
        case .leftElbow, .rightElbow: JointLimits(bend: 0...150, twist: 0...0, side: 0...0)
        case .leftWrist, .rightWrist: JointLimits(bend: -70...70, twist: -80...80, side: -25...35)
        case .leftHip, .rightHip: JointLimits(bend: -30...125, twist: -60...60, side: -15...60)
        case .leftKnee, .rightKnee: JointLimits(bend: 0...150, twist: 0...0, side: 0...0)
        case .leftAnkle, .rightAnkle: JointLimits(bend: -45...30, twist: 0...0, side: -20...20)
        }
    }

    /// Plain-language names for the axes this joint can turn on.
    func label(for axis: JointAxis) -> String {
        switch (self, axis) {
        case (.pelvis, .bend), (.spine, .bend), (.chest, .bend): "Lean Forward"
        case (.neck, .bend), (.head, .bend): "Nod Down"
        case (.pelvis, .twist), (.spine, .twist), (.chest, .twist), (.neck, .twist), (.head, .twist): "Turn Left"
        case (.pelvis, .side), (.spine, .side), (.chest, .side), (.neck, .side), (.head, .side): "Tilt Left"
        case (.leftShoulder, .bend), (.rightShoulder, .bend), (.leftHip, .bend), (.rightHip, .bend): "Raise Forward"
        case (.leftShoulder, .side), (.rightShoulder, .side), (.leftHip, .side), (.rightHip, .side): "Raise Out"
        case (.leftShoulder, .twist), (.rightShoulder, .twist), (.leftHip, .twist), (.rightHip, .twist): "Rotate In"
        case (.leftElbow, _), (.rightElbow, _), (.leftKnee, _), (.rightKnee, _): "Bend"
        case (.leftWrist, .bend), (.rightWrist, .bend): "Flex"
        case (.leftWrist, .twist), (.rightWrist, .twist): "Turn In"
        case (.leftWrist, .side), (.rightWrist, .side): "Tilt Out"
        case (.leftAnkle, .bend), (.rightAnkle, .bend): "Toes Up"
        case (.leftAnkle, _), (.rightAnkle, _): "Roll Out"
        }
    }

    /// The axes this joint can turn on (an elbow only bends).
    var axes: [JointAxis] { JointAxis.allCases.filter { limits.range(for: $0).lowerBound < limits.range(for: $0).upperBound } }
}

enum JointAxis: String, CaseIterable, Identifiable {
    case bend, side, twist
    var id: String { rawValue }
}

struct JointLimits: Equatable {
    var bend: ClosedRange<Float>
    var twist: ClosedRange<Float>
    var side: ClosedRange<Float>

    func range(for axis: JointAxis) -> ClosedRange<Float> {
        switch axis {
        case .bend: bend
        case .twist: twist
        case .side: side
        }
    }

    func clamp(_ rotation: JointRotation) -> JointRotation {
        func clamp(_ value: Float, _ range: ClosedRange<Float>) -> Float { min(max(value, range.lowerBound), range.upperBound) }
        return JointRotation(bend: clamp(rotation.bend, bend), twist: clamp(rotation.twist, twist),
                             side: clamp(rotation.side, side))
    }
}

/// A joint's turn away from standing straight, in degrees on each axis.
struct JointRotation: Codable, Equatable {
    var bend: Float = 0
    var twist: Float = 0
    var side: Float = 0

    static let zero = JointRotation()

    subscript(axis: JointAxis) -> Float {
        get {
            switch axis {
            case .bend: bend
            case .twist: twist
            case .side: side
            }
        }
        set {
            switch axis {
            case .bend: bend = newValue
            case .twist: twist = newValue
            case .side: side = newValue
            }
        }
    }

    var isZero: Bool { abs(bend) < 0.01 && abs(twist) < 0.01 && abs(side) < 0.01 }
}

// MARK: Poses

/// Every joint's rotation for one character. Joints left out stand straight.
///
/// Angles are always kept within each joint's limits. The limits never reach ±180° on an
/// axis that could wrap around, so blending two poses angle by angle always takes the
/// direct route, without the sudden flips that interpolating raw rotations can produce.
struct CharacterPose: Codable, Equatable {
    private(set) var rotations: [Joint: JointRotation] = [:]

    static let neutral = CharacterPose()

    init(_ rotations: [Joint: JointRotation] = [:]) {
        for (joint, rotation) in rotations { self[joint] = rotation }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode([Joint: JointRotation].self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rotations)
    }

    subscript(joint: Joint) -> JointRotation {
        get { rotations[joint] ?? .zero }
        set {
            let clamped = joint.limits.clamp(newValue)
            rotations[joint] = clamped.isZero ? nil : clamped
        }
    }

    var isNeutral: Bool { rotations.isEmpty }

    /// The same pose with left and right swapped, as if seen in a mirror: a right-hand wave
    /// becomes a left-hand wave, and turning left becomes turning right.
    var mirrored: CharacterPose {
        var result = CharacterPose()
        for joint in Joint.allCases {
            var rotation = self[joint]
            if joint.mirror == joint {
                // Joints on the center line: lean stays, turn and tilt swap direction.
                rotation.twist = -rotation.twist
                rotation.side = -rotation.side
                result[joint] = rotation
            } else {
                // Limb angles mean the same thing on either side, so they move across as is.
                result[joint.mirror] = rotation
            }
        }
        return result
    }

    /// Partway from this pose to `other`: 0 is this pose, 1 is `other`.
    func interpolated(to other: CharacterPose, _ t: Float) -> CharacterPose {
        var result = CharacterPose()
        for joint in Set(rotations.keys).union(other.rotations.keys) {
            let a = self[joint], b = other[joint]
            result[joint] = JointRotation(bend: a.bend + (b.bend - a.bend) * t,
                                          twist: a.twist + (b.twist - a.twist) * t,
                                          side: a.side + (b.side - a.side) * t)
        }
        return result
    }

    /// True when every joint is within `tolerance` degrees of the other pose.
    func matches(_ other: CharacterPose, tolerance: Float = 0.5) -> Bool {
        for joint in Set(rotations.keys).union(other.rotations.keys) {
            let a = self[joint], b = other[joint]
            if abs(a.bend - b.bend) > tolerance || abs(a.twist - b.twist) > tolerance || abs(a.side - b.side) > tolerance {
                return false
            }
        }
        return true
    }

    static func matches(_ a: [ObjectID: CharacterPose], _ b: [ObjectID: CharacterPose]) -> Bool {
        guard Set(a.keys) == Set(b.keys) else { return false }
        return a.allSatisfy { id, pose in b[id].map { pose.matches($0) } ?? false }
    }
}

// MARK: Body shape

/// The adjustable proportions of a built-in character. 1 is the mannequin's default.
struct CharacterProportions: Codable, Equatable, Hashable {
    /// Overall size.
    var height: Float = 1
    /// Shoulder and hip width, and how thick the limbs are.
    var build: Float = 1
    var head: Float = 1
    /// Leg length relative to the body.
    var legs: Float = 1

    static let heightRange: ClosedRange<Float> = 0.5...1.3
    static let buildRange: ClosedRange<Float> = 0.75...1.4
    static let headRange: ClosedRange<Float> = 0.8...1.35
    static let legsRange: ClosedRange<Float> = 0.8...1.2

    var clamped: CharacterProportions {
        func clamp(_ value: Float, _ range: ClosedRange<Float>) -> Float { min(max(value, range.lowerBound), range.upperBound) }
        return CharacterProportions(height: clamp(height, Self.heightRange), build: clamp(build, Self.buildRange),
                                    head: clamp(head, Self.headRange), legs: clamp(legs, Self.legsRange))
    }
}

/// The built-in characters. All share the same fully poseable rig; they differ in their
/// starting proportions and color.
enum CharacterKind: String, CaseIterable, Codable, Identifiable {
    case mannequin, child, stocky

    var id: String { rawValue }

    var name: String {
        switch self {
        case .mannequin: "Mannequin"
        case .child: "Child"
        case .stocky: "Stocky Figure"
        }
    }

    var symbol: String {
        switch self {
        case .mannequin: "figure.stand"
        case .child: "figure.child"
        case .stocky: "figure.arms.open"
        }
    }

    var proportions: CharacterProportions {
        switch self {
        case .mannequin: CharacterProportions()
        case .child: CharacterProportions(height: 0.62, build: 0.9, head: 1.28, legs: 0.86)
        case .stocky: CharacterProportions(height: 0.97, build: 1.3, head: 1, legs: 0.92)
        }
    }

    var keywords: [String] {
        switch self {
        case .mannequin: ["mannequin", "person", "man", "woman", "human", "figure", "character", "actor", "people"]
        case .child: ["child", "kid", "boy", "girl", "toddler"]
        case .stocky: ["stocky", "big guy", "strongman", "giant"]
        }
    }
}

// MARK: Layout and kinematics

/// Where each joint sits relative to its parent, for a body with given proportions. The
/// rig is laid out at human size, in meters, standing straight with arms at its sides;
/// the scene shrinks it to miniature scale.
struct RigLayout {
    /// The mannequin's real-world height at proportions of 1.
    static let humanHeight: Float = 1.75
    /// How much smaller than life the characters are in the miniature: about 5 cm tall.
    static let miniatureScale: Float = 1.0 / 35

    let proportions: CharacterProportions

    var upperArm: Float { 0.29 }
    var forearm: Float { 0.26 }
    var thigh: Float { 0.44 * proportions.legs }
    var shin: Float { 0.43 * proportions.legs }
    var ankleHeight: Float { 0.075 }
    var hipHeight: Float { 0.05 + thigh + shin + ankleHeight }

    func offset(of joint: Joint) -> SIMD3<Float> {
        let build = proportions.build
        switch joint {
        case .pelvis: return [0, hipHeight, 0]
        case .spine: return [0, 0.10, 0]
        case .chest: return [0, 0.20, 0]
        case .neck: return [0, 0.22, 0]
        case .head: return [0, 0.08, 0]
        case .leftShoulder: return [0.18 * build, 0.17, 0]
        case .rightShoulder: return [-0.18 * build, 0.17, 0]
        case .leftElbow, .rightElbow: return [0, -upperArm, 0]
        case .leftWrist, .rightWrist: return [0, -forearm, 0]
        case .leftHip: return [0.09 * build, -0.05, 0]
        case .rightHip: return [-0.09 * build, -0.05, 0]
        case .leftKnee, .rightKnee: return [0, -thigh, 0]
        case .leftAnkle, .rightAnkle: return [0, -shin, 0]
        }
    }
}

enum CharacterKinematics {
    /// The rotation a joint's angles describe, relative to its parent.
    /// Twist turns the segment about its own length first, then it bends, then tilts sideways.
    static func rotation(_ angles: JointRotation, for joint: Joint) -> simd_quatf {
        let signs = joint.signs
        let toRadians = Float.pi / 180
        let bend = simd_quatf(angle: angles.bend * signs.x * toRadians, axis: [1, 0, 0])
        let twist = simd_quatf(angle: angles.twist * signs.y * toRadians, axis: [0, 1, 0])
        let side = simd_quatf(angle: angles.side * signs.z * toRadians, axis: [0, 0, 1])
        return side * bend * twist
    }

    /// The angles that produce a rotation (the inverse of `rotation(_:for:)`), not yet limited.
    static func angles(from rotation: simd_quatf, for joint: Joint) -> JointRotation {
        let m = simd_matrix3x3(rotation)
        // m = Rz(side) · Rx(bend) · Ry(twist); see the matrix product's entries.
        let bend = asin(min(max(m.columns.1.z, -1), 1))
        var twist = atan2(-m.columns.0.z, m.columns.2.z)
        var side = atan2(-m.columns.1.x, m.columns.1.y)
        if abs(m.columns.1.z) > 0.9995 {
            // Bent straight forward or back, twist and side turn about the same axis. Put it all
            // in side, so angles don't swap back and forth while dragging through this point.
            twist = 0
            side = atan2(m.columns.0.y, m.columns.0.x)
        }
        let toDegrees = 180 / Float.pi
        let signs = joint.signs
        return JointRotation(bend: bend * toDegrees * (signs.x == 0 ? 0 : signs.x),
                             twist: twist * toDegrees * (signs.y == 0 ? 0 : signs.y),
                             side: side * toDegrees * (signs.z == 0 ? 0 : signs.z))
    }

    /// Turns a joint so its segment follows a drag. `from` is where the drag started and `to`
    /// is where it is now, both as directions from the joint, in its parent's space. The
    /// turn is relative to `start` (the joint's angles when the drag began), so the segment
    /// doesn't jump to point at the spot that was pinched. Kept within the joint's limits; a
    /// hinge such as an elbow only bends.
    static func swing(_ joint: Joint, startingAt start: JointRotation,
                      from: SIMD3<Float>, to: SIMD3<Float>) -> JointRotation {
        guard simd_length(from) > 1e-5, simd_length(to) > 1e-5 else { return start }
        let turn = simd_quatf(from: simd_normalize(from), to: simd_normalize(to))
        return joint.limits.clamp(angles(from: turn * rotation(start, for: joint), for: joint))
    }

    struct JointFrame {
        var position: SIMD3<Float>
        var orientation: simd_quatf
    }

    /// Where every joint is, and which way it faces, in the rig's own space (before grounding).
    static func frames(for pose: CharacterPose, layout: RigLayout) -> [Joint: JointFrame] {
        var frames: [Joint: JointFrame] = [:]
        for joint in Joint.allCases {
            let local = rotation(pose[joint], for: joint)
            if let parent = joint.parent, let parentFrame = frames[parent] {
                frames[joint] = JointFrame(position: parentFrame.position + parentFrame.orientation.act(layout.offset(of: joint)),
                                           orientation: parentFrame.orientation * local)
            } else {
                frames[joint] = JointFrame(position: layout.offset(of: joint), orientation: local)
            }
        }
        return frames
    }
}

// MARK: Inverse kinematics

/// An arm or leg, for placing its hand or foot directly and letting the limb bend to reach.
enum Limb: String, CaseIterable, Identifiable {
    case leftArm, rightArm, leftLeg, rightLeg

    var id: String { rawValue }

    /// The shoulder or hip.
    var root: Joint {
        switch self {
        case .leftArm: .leftShoulder
        case .rightArm: .rightShoulder
        case .leftLeg: .leftHip
        case .rightLeg: .rightHip
        }
    }

    /// The elbow or knee.
    var middle: Joint {
        switch self {
        case .leftArm: .leftElbow
        case .rightArm: .rightElbow
        case .leftLeg: .leftKnee
        case .rightLeg: .rightKnee
        }
    }

    /// The wrist or ankle: the point being placed.
    var end: Joint {
        switch self {
        case .leftArm: .leftWrist
        case .rightArm: .rightWrist
        case .leftLeg: .leftAnkle
        case .rightLeg: .rightAnkle
        }
    }

    init?(end joint: Joint) {
        guard let limb = Limb.allCases.first(where: { $0.end == joint }) else { return nil }
        self = limb
    }

    var isArm: Bool { self == .leftArm || self == .rightArm }
    private var isLeft: Bool { self == .leftArm || self == .leftLeg }

    /// "Elbow" or "Knee", for the bend-direction control.
    var middleName: String { isArm ? "Elbow" : "Knee" }

    /// Which way the elbow or knee points at a bend direction of 0: elbows back, knees forward.
    var restingBendDirection: SIMD3<Float> { isArm ? [0, 0, -1] : [0, 0, 1] }

    /// Turns positive bend directions outward, away from the body, on either side.
    var bendDirectionSign: Float {
        switch self {
        case .leftArm, .rightLeg: 1
        case .rightArm, .leftLeg: -1
        }
    }

    /// Sideways direction away from the body, in the limb's parent space.
    var outward: Float { isLeft ? 1 : -1 }
}

enum LimbIK {
    /// The hand or foot's position relative to the shoulder or hip, in the shoulder's or
    /// hip's parent space (the chest or pelvis), at human scale in meters.
    static func effector(of limb: Limb, in pose: CharacterPose, layout: RigLayout) -> SIMD3<Float> {
        let frames = CharacterKinematics.frames(for: pose, layout: layout)
        guard let parent = limb.root.parent, let parentFrame = frames[parent],
              let root = frames[limb.root], let end = frames[limb.end] else { return .zero }
        return parentFrame.orientation.inverse.act(end.position - root.position)
    }

    /// The direction the elbow or knee points around the line from shoulder to hand, in
    /// degrees. 0 is the natural direction; positive turns it outward.
    static func bendDirection(of limb: Limb, in pose: CharacterPose, layout: RigLayout) -> Float {
        let frames = CharacterKinematics.frames(for: pose, layout: layout)
        guard let parent = limb.root.parent, let parentFrame = frames[parent],
              let root = frames[limb.root], let middle = frames[limb.middle], let end = frames[limb.end] else { return 0 }
        let toLocal = parentFrame.orientation.inverse
        let reach = toLocal.act(end.position - root.position)
        let elbow = toLocal.act(middle.position - root.position)
        guard simd_length(reach) > 1e-4 else { return 0 }
        let axis = simd_normalize(reach)
        let bent = perpendicular(elbow, to: axis)
        let natural = perpendicular(limb.restingBendDirection, to: axis)
        guard simd_length(bent) > 1e-4, simd_length(natural) > 1e-4 else { return 0 }
        let angle = signedAngle(from: natural, to: bent, around: axis)
        return angle * 180 / .pi * limb.bendDirectionSign
    }

    /// Bends a limb so its hand or foot reaches `target` (relative to the shoulder or hip, in
    /// its parent's space). Out-of-reach targets are reached as far as the limb allows.
    /// The elbow or knee points along `bendDirection` (degrees, see `bendDirection(of:in:layout:)`).
    /// Only the shoulder or hip and the elbow or knee change, within their joint limits;
    /// the hand or foot keeps its own angle.
    static func solve(_ limb: Limb, reaching target: SIMD3<Float>, bendDirection: Float,
                      pose: CharacterPose, layout: RigLayout) -> CharacterPose {
        let upper = simd_length(layout.offset(of: limb.middle))
        let lower = simd_length(layout.offset(of: limb.end))
        let distance = min(max(simd_length(target), abs(upper - lower) + 1e-3), (upper + lower) * 0.9995)

        // Law of cosines: how far the elbow or knee must bend for this distance.
        let cosInner = (upper * upper + lower * lower - distance * distance) / (2 * upper * lower)
        let bend = (Float.pi - acos(min(max(cosInner, -1), 1))) * 180 / .pi
        var middleAngles = JointRotation()
        middleAngles.bend = bend
        middleAngles = limb.middle.limits.clamp(middleAngles)

        // Where the hand ends up with the shoulder straight, then turn the whole limb onto the target.
        let middleRotation = CharacterKinematics.rotation(middleAngles, for: limb.middle)
        let restingEnd = layout.offset(of: limb.middle) + middleRotation.act(layout.offset(of: limb.end))
        let direction = simd_length(target) > 1e-5 ? simd_normalize(target) : SIMD3<Float>(0, -1, 0)
        let align = simd_quatf(from: simd_normalize(restingEnd), to: direction)

        // Then spin the limb around that line until the elbow or knee points the chosen way.
        let elbow = perpendicular(align.act(layout.offset(of: limb.middle)), to: direction)
        let natural = perpendicular(limb.restingBendDirection, to: direction)
        var spin: Float = 0
        if simd_length(elbow) > 1e-5, simd_length(natural) > 1e-5 {
            let turn = bendDirection * limb.bendDirectionSign * .pi / 180
            let wanted = simd_quatf(angle: turn, axis: direction).act(natural)
            spin = signedAngle(from: elbow, to: wanted, around: direction)
        }
        let rootRotation = simd_quatf(angle: spin, axis: direction) * align

        var result = pose
        result[limb.root] = CharacterKinematics.angles(from: rootRotation, for: limb.root)
        result[limb.middle] = middleAngles
        return result
    }

    private static func perpendicular(_ vector: SIMD3<Float>, to axis: SIMD3<Float>) -> SIMD3<Float> {
        vector - simd_dot(vector, axis) * axis
    }

    private static func signedAngle(from a: SIMD3<Float>, to b: SIMD3<Float>, around axis: SIMD3<Float>) -> Float {
        atan2(simd_dot(simd_cross(a, b), axis), simd_dot(a, b))
    }
}
