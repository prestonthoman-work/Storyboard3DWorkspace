//
//  KeyframeTimeline.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit
import simd

/// A snapshot of every placed object's pose at one moment.
struct Keyframe: Identifiable {
    let id = UUID()
    var time: TimeInterval
    /// Each object's position, rotation, and scale relative to the base.
    var poses: [Entity.ID: Transform]
}

/// An ordered list of evenly spaced keyframes, with eased interpolation between them.
///
/// A keyframe may be empty. An object is shown only from keyframes that include it: it
/// appears at the first such keyframe and is hidden at keyframes without it. Objects that
/// aren't in any keyframe aren't animated and stay visible.
struct KeyframeTimeline {
    static let spacing: TimeInterval = 1

    private(set) var keyframes: [Keyframe] = []

    var duration: TimeInterval { keyframes.last?.time ?? 0 }
    var canPlay: Bool { keyframes.count >= 2 }

    @discardableResult
    mutating func append(_ poses: [Entity.ID: Transform]) -> Keyframe {
        let keyframe = Keyframe(time: keyframes.isEmpty ? 0 : duration + Self.spacing, poses: poses)
        keyframes.append(keyframe)
        return keyframe
    }

    mutating func update(_ id: Keyframe.ID, with poses: [Entity.ID: Transform]) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[index].poses = poses
    }

    mutating func remove(_ id: Keyframe.ID) {
        keyframes.removeAll { $0.id == id }
        // Close the gap so keyframes stay evenly spaced.
        for index in keyframes.indices {
            keyframes[index].time = TimeInterval(index) * Self.spacing
        }
    }

    func keyframe(_ id: Keyframe.ID?) -> Keyframe? {
        keyframes.first { $0.id == id }
    }

    func keyframe(near time: TimeInterval, tolerance: TimeInterval = 0.03) -> Keyframe? {
        keyframes.first { abs($0.time - time) <= tolerance }
    }

    /// True when both snapshots hold the same objects in the same poses, within small
    /// tolerances (a couple of millimeters, about a degree).
    static func posesMatch(_ a: [Entity.ID: Transform], _ b: [Entity.ID: Transform]) -> Bool {
        guard Set(a.keys) == Set(b.keys) else { return false }
        for (id, poseA) in a {
            guard let poseB = b[id] else { return false }
            if simd_distance(poseA.translation, poseB.translation) > 0.002 { return false }
            if simd_distance(poseA.scale, poseB.scale) > 0.002 { return false }
            if abs(simd_dot(poseA.rotation.vector, poseB.rotation.vector)) < 0.99996 { return false }
        }
        return true
    }

    /// Every object that appears in at least one keyframe.
    var keyframedObjectIDs: Set<Entity.ID> {
        Set(keyframes.flatMap { $0.poses.keys })
    }

    /// The interpolated pose at `time` of every object visible then. Keyframed objects
    /// missing from the result are hidden at that time.
    func poses(at time: TimeInterval) -> [Entity.ID: Transform] {
        // The keyframe in effect: the last one at or before `time`, else the first.
        guard let governing = keyframes.last(where: { $0.time <= time + 1e-6 }) ?? keyframes.first else { return [:] }

        var result: [Entity.ID: Transform] = [:]
        for objectID in governing.poses.keys {
            let track = keyframes.compactMap { keyframe in keyframe.poses[objectID].map { (keyframe.time, $0) } }
            if let pose = Self.interpolate(track, at: time) { result[objectID] = pose }
        }
        return result
    }

    /// Removes a deleted object from every keyframe.
    /// - Returns: The keyframes that contained it.
    mutating func removeObject(_ objectID: Entity.ID) -> [Keyframe.ID] {
        var changed: [Keyframe.ID] = []
        for index in keyframes.indices where keyframes[index].poses[objectID] != nil {
            keyframes[index].poses[objectID] = nil
            changed.append(keyframes[index].id)
        }
        return changed
    }

    private static func interpolate(_ track: [(time: TimeInterval, pose: Transform)], at time: TimeInterval) -> Transform? {
        guard let first = track.first, let last = track.last else { return nil }
        if time <= first.time { return first.pose }
        if time >= last.time { return last.pose }

        guard let nextIndex = track.firstIndex(where: { $0.time > time }), nextIndex > 0 else { return last.pose }
        let from = track[nextIndex - 1]
        let to = track[nextIndex]
        let linear = Float((time - from.time) / (to.time - from.time))
        let eased = linear * linear * (3 - 2 * linear) // smoothstep: ease in and out of each pose

        return Transform(
            scale: mix(from.pose.scale, to.pose.scale, t: eased),
            rotation: simd_slerp(from.pose.rotation, to.pose.rotation, eased),
            translation: mix(from.pose.translation, to.pose.translation, t: eased)
        )
    }
}
