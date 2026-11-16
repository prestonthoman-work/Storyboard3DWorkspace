//
//  BodyCollision.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// Keeps a character's body parts from passing through each other while it's posed.
///
/// The body is approximated by capsules a little slimmer than the visible mannequin, so
/// parts can touch and overlap slightly, the way the real figure's rounded pieces do, but
/// an arm can't sink into the chest or one leg pass through the other.
enum BodyCollision {
    /// How far two capsules may overlap before it counts, at life size in meters.
    static let allowedOverlap: Float = 0.012

    enum Part: CaseIterable {
        case pelvis, abdomen, chest, head
        case leftUpperArm, leftForearm, leftHand, rightUpperArm, rightForearm, rightHand
        case leftThigh, leftShin, leftFoot, rightThigh, rightShin, rightFoot

        var isArm: Bool { [.leftUpperArm, .leftForearm, .leftHand, .rightUpperArm, .rightForearm, .rightHand].contains(self) }
        var isLeg: Bool { [.leftThigh, .leftShin, .leftFoot, .rightThigh, .rightShin, .rightFoot].contains(self) }
        var isLeft: Bool { [.leftUpperArm, .leftForearm, .leftHand, .leftThigh, .leftShin, .leftFoot].contains(self) }
        var isTorso: Bool { !isArm && !isLeg }
    }

    struct Capsule {
        var a: SIMD3<Float>
        var b: SIMD3<Float>
        var radius: Float
    }

    /// The part pairs that are checked. Parts joined at a joint (a thigh and the hips) are
    /// left out, since they always meet there.
    static let pairs: [(Part, Part)] = {
        var pairs: [(Part, Part)] = []
        let parts = Part.allCases
        for (i, a) in parts.enumerated() {
            for b in parts[(i + 1)...] {
                let checked: Bool
                switch (a, b) {
                case _ where a.isTorso && b.isTorso:
                    checked = (a == .head && b == .chest) || (a == .chest && b == .head)
                case _ where a.isArm && b.isArm:
                    checked = a.isLeft != b.isLeft
                case _ where a.isLeg && b.isLeg:
                    checked = a.isLeft != b.isLeft
                case (.pelvis, .leftThigh), (.pelvis, .rightThigh):
                    checked = false
                default:
                    checked = true
                }
                if checked { pairs.append((a, b)) }
            }
        }
        return pairs
    }()

    /// Every part's capsule for a pose, in the rig's space.
    static func capsules(for pose: CharacterPose, layout: RigLayout) -> [Part: Capsule] {
        let frames = CharacterKinematics.frames(for: pose, layout: layout)
        let build = layout.proportions.build
        let head = layout.proportions.head
        func capsule(_ joint: Joint, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ radius: Float) -> Capsule {
            let frame = frames[joint]!
            return Capsule(a: frame.position + frame.orientation.act(a), b: frame.position + frame.orientation.act(b), radius: radius)
        }
        let upperArm = layout.upperArm, forearm = layout.forearm, thigh = layout.thigh, shin = layout.shin
        return [
            .pelvis: capsule(.pelvis, [-0.06 * build, -0.03, 0], [0.06 * build, -0.03, 0], 0.085 * build),
            .abdomen: capsule(.spine, [0, 0.04, 0], [0, 0.16, 0], 0.085 * build),
            .chest: capsule(.chest, [-0.05 * build, 0.13, 0], [0.05 * build, 0.13, 0], 0.10 * build),
            .head: capsule(.head, [0, 0.11 * head, 0], [0, 0.11 * head, 0], 0.10 * head),
            // The upper arm and thigh start partway down, clear of the shoulder and hip they hang from.
            .leftUpperArm: capsule(.leftShoulder, [0, -0.3 * upperArm, 0], [0, -upperArm, 0], 0.038 * build),
            .rightUpperArm: capsule(.rightShoulder, [0, -0.3 * upperArm, 0], [0, -upperArm, 0], 0.038 * build),
            .leftForearm: capsule(.leftElbow, [0, -0.02, 0], [0, -forearm, 0], 0.036 * build),
            .rightForearm: capsule(.rightElbow, [0, -0.02, 0], [0, -forearm, 0], 0.036 * build),
            .leftHand: capsule(.leftWrist, [0, -0.04, 0], [0, -0.16, 0], 0.03),
            .rightHand: capsule(.rightWrist, [0, -0.04, 0], [0, -0.16, 0], 0.03),
            .leftThigh: capsule(.leftHip, [0, -0.25 * thigh, 0], [0, -thigh, 0], 0.055 * build),
            .rightThigh: capsule(.rightHip, [0, -0.25 * thigh, 0], [0, -thigh, 0], 0.055 * build),
            .leftShin: capsule(.leftKnee, [0, -0.02, 0], [0, -shin, 0], 0.045 * build),
            .rightShin: capsule(.rightKnee, [0, -0.02, 0], [0, -shin, 0], 0.045 * build),
            .leftFoot: capsule(.leftAnkle, [0, -0.04, -0.04], [0, -0.04, 0.16], 0.035 * build),
            .rightFoot: capsule(.rightAnkle, [0, -0.04, -0.04], [0, -0.04, 0.16], 0.035 * build),
        ]
    }

    /// How far two parts sink into each other beyond the allowed overlap (0 when they don't).
    static func depth(_ a: Capsule, _ b: Capsule) -> Float {
        max(0, a.radius + b.radius - segmentDistance(a.a, a.b, b.a, b.b) - allowedOverlap)
    }

    /// The total amount body parts sink into each other in a pose. 0 is a clean pose.
    static func penetration(of pose: CharacterPose, layout: RigLayout) -> Float {
        let capsules = capsules(for: pose, layout: layout)
        return pairs.reduce(0) { total, pair in total + depth(capsules[pair.0]!, capsules[pair.1]!) }
    }

    /// The parts that sink into each other in a pose, for diagnostics and tests.
    static func contacts(in pose: CharacterPose, layout: RigLayout) -> [(Part, Part, Float)] {
        let capsules = capsules(for: pose, layout: layout)
        return pairs.compactMap { pair in
            let depth = depth(capsules[pair.0]!, capsules[pair.1]!)
            return depth > 0 ? (pair.0, pair.1, depth) : nil
        }
    }

    /// Moves from `current` toward `candidate` as far as the body allows. A part that would
    /// sink into another stops at its surface, while any turn that's still free carries on,
    /// so a limb slides along the body instead of sticking. Poses that already overlap (some
    /// presets do) never lock up: moves just can't make the overlap worse. Large changes are
    /// taken in small steps so a limb can't skip through the body.
    static func resolve(from current: CharacterPose, toward candidate: CharacterPose, layout: RigLayout) -> CharacterPose {
        var largest: Float = 0
        for joint in Joint.allCases {
            let a = current[joint], b = candidate[joint]
            largest = max(largest, abs(a.bend - b.bend), abs(a.twist - b.twist), abs(a.side - b.side))
        }
        guard largest > 0.001 else { return candidate }
        let steps = max(1, Int((largest / 8).rounded(.up)))
        var pose = current
        for step in 1...steps {
            let target = current.interpolated(to: candidate, Float(step) / Float(steps))
            pose = resolveStep(from: pose, toward: target, layout: layout)
        }
        return pose
    }

    private static func resolveStep(from current: CharacterPose, toward candidate: CharacterPose, layout: RigLayout) -> CharacterPose {
        let limit = penetration(of: current, layout: layout) + 1e-7
        func isAllowed(_ pose: CharacterPose) -> Bool { penetration(of: pose, layout: layout) <= limit }
        if isAllowed(candidate) { return candidate }

        // Keep every individual turn that's free on its own: this is the sliding.
        var slid = current
        for joint in Joint.allCases {
            for axis in JointAxis.allCases where abs(current[joint][axis] - candidate[joint][axis]) > 0.0001 {
                var trial = slid
                var rotation = trial[joint]
                rotation[axis] = candidate[joint][axis]
                trial[joint] = rotation
                if isAllowed(trial) { slid = trial }
            }
        }
        // Then go as far toward the rest of the change as possible, stopping at contact.
        var low: Float = 0, high: Float = 1
        for _ in 0..<10 {
            let middle = (low + high) / 2
            if isAllowed(slid.interpolated(to: candidate, middle)) { low = middle } else { high = middle }
        }
        return slid.interpolated(to: candidate, low)
    }

    /// The shortest distance between two line segments.
    private static func segmentDistance(_ p1: SIMD3<Float>, _ q1: SIMD3<Float>, _ p2: SIMD3<Float>, _ q2: SIMD3<Float>) -> Float {
        let d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2
        let a = simd_dot(d1, d1), e = simd_dot(d2, d2), f = simd_dot(d2, r)
        var s: Float = 0, t: Float = 0
        if a <= 1e-8 && e <= 1e-8 { return simd_distance(p1, p2) }
        if a <= 1e-8 {
            t = min(max(f / e, 0), 1)
        } else {
            let c = simd_dot(d1, r)
            if e <= 1e-8 {
                s = min(max(-c / a, 0), 1)
            } else {
                let b = simd_dot(d1, d2)
                let denominator = a * e - b * b
                s = denominator > 1e-8 ? min(max((b * f - c * e) / denominator, 0), 1) : 0
                t = (b * s + f) / e
                if t < 0 {
                    t = 0
                    s = min(max(-c / a, 0), 1)
                } else if t > 1 {
                    t = 1
                    s = min(max((b - c) / a, 0), 1)
                }
            }
        }
        return simd_distance(p1 + d1 * s, p2 + d2 * t)
    }
}
