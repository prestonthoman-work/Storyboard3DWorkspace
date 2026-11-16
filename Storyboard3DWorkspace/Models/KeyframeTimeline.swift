//
//  KeyframeTimeline.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit
import simd

/// A snapshot of every placed object's pose at one moment.
struct Keyframe: Identifiable {
    var id = UUID()
    var time: TimeInterval
    /// Each object's position, rotation, and scale relative to the base.
    var poses: [ObjectID: Transform]
    /// Free-form shot notes, printed on the storyboard sheet.
    var note = ""
    /// How the shot is framed: wide, close-up, and so on.
    var shotType: ShotType?
    /// Each character's body pose. Where the character stands is in `poses`.
    var characterPoses: [ObjectID: CharacterPose] = [:]
    /// Hold this keyframe until the next one, then cut, instead of easing between them.
    /// For storyboards made of distinct poses rather than smooth animation.
    var holds = false
}

/// An ordered list of keyframes, each at its own time, with eased interpolation between them.
///
/// The first keyframe is always at 0. New keyframes land one `spacing` after the one before,
/// and can be dragged to new times as long as they stay in order.
///
/// A keyframe may be empty. An object is shown only from keyframes that include it: it
/// appears at the first such keyframe and is hidden at keyframes without it. Objects that
/// aren't in any keyframe aren't animated and stay visible.
struct KeyframeTimeline {
    static let spacing: TimeInterval = 1
    /// The closest two keyframes can be.
    static let minimumGap: TimeInterval = 0.2
    /// Retimed keyframes snap to this grid.
    static let snapStep: TimeInterval = 0.1

    private(set) var keyframes: [Keyframe] = []

    init(keyframes: [Keyframe] = []) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    var duration: TimeInterval { keyframes.last?.time ?? 0 }
    var canPlay: Bool { keyframes.count >= 2 }

    func index(of id: Keyframe.ID) -> Int? {
        keyframes.firstIndex { $0.id == id }
    }

    @discardableResult
    mutating func append(_ poses: [ObjectID: Transform], characters: [ObjectID: CharacterPose] = [:]) -> Keyframe {
        let keyframe = Keyframe(time: keyframes.isEmpty ? 0 : duration + Self.spacing, poses: poses, characterPoses: characters)
        keyframes.append(keyframe)
        return keyframe
    }

    /// Adds a keyframe right after another one. Everything later moves back one `spacing`,
    /// so the timing between the existing keyframes doesn't change.
    @discardableResult
    mutating func insert(_ poses: [ObjectID: Transform], characters: [ObjectID: CharacterPose] = [:],
                         after id: Keyframe.ID, note: String = "", shotType: ShotType? = nil,
                         holds: Bool = false) -> Keyframe? {
        guard let index = index(of: id) else { return nil }
        for later in keyframes.indices where later > index {
            keyframes[later].time += Self.spacing
        }
        let keyframe = Keyframe(time: keyframes[index].time + Self.spacing, poses: poses, note: note, shotType: shotType,
                                characterPoses: characters, holds: holds)
        keyframes.insert(keyframe, at: index + 1)
        return keyframe
    }

    /// Adds a keyframe at a moment between two others, without moving any.
    /// - Returns: Nil when `time` is outside the timeline or too close to a keyframe.
    @discardableResult
    mutating func insert(_ poses: [ObjectID: Transform], characters: [ObjectID: CharacterPose] = [:],
                         at time: TimeInterval) -> Keyframe? {
        guard let next = keyframes.firstIndex(where: { $0.time > time }), next > 0,
              time - keyframes[next - 1].time >= Self.minimumGap / 2,
              keyframes[next].time - time >= Self.minimumGap / 2
        else { return nil }
        let keyframe = Keyframe(time: time, poses: poses, characterPoses: characters)
        keyframes.insert(keyframe, at: next)
        return keyframe
    }

    /// A copy of a keyframe, placed right after it.
    @discardableResult
    mutating func duplicate(_ id: Keyframe.ID) -> Keyframe? {
        guard let original = keyframe(id) else { return nil }
        return insert(original.poses, characters: original.characterPoses, after: id, note: original.note,
                      shotType: original.shotType, holds: original.holds)
    }

    /// The time a keyframe would land at if dragged to `time`: snapped to the grid and kept
    /// between its neighbors. The first keyframe stays at 0.
    func allowedTime(for id: Keyframe.ID, near time: TimeInterval) -> TimeInterval? {
        guard let index = index(of: id) else { return nil }
        guard index > 0 else { return 0 }
        let snapped = (time / Self.snapStep).rounded() * Self.snapStep
        let lower = keyframes[index - 1].time + Self.minimumGap
        let upper = index + 1 < keyframes.count ? keyframes[index + 1].time - Self.minimumGap : .infinity
        return min(max(snapped, lower), upper)
    }

    /// Moves a keyframe to a new time between its neighbors.
    /// - Returns: True if its time changed.
    @discardableResult
    mutating func retime(_ id: Keyframe.ID, to time: TimeInterval) -> Bool {
        guard let index = index(of: id), let allowed = allowedTime(for: id, near: time),
              abs(keyframes[index].time - allowed) > 1e-6 else { return false }
        keyframes[index].time = allowed
        return true
    }

    mutating func update(_ id: Keyframe.ID, with poses: [ObjectID: Transform], characters: [ObjectID: CharacterPose] = [:]) {
        guard let index = index(of: id) else { return }
        keyframes[index].poses = poses
        keyframes[index].characterPoses = characters
    }

    mutating func setHolds(_ holds: Bool, for id: Keyframe.ID) {
        guard let index = index(of: id) else { return }
        keyframes[index].holds = holds
    }

    mutating func setShotType(_ shotType: ShotType?, for id: Keyframe.ID) {
        guard let index = index(of: id) else { return }
        keyframes[index].shotType = shotType
    }

    mutating func setNote(_ note: String, for id: Keyframe.ID) {
        guard let index = index(of: id) else { return }
        keyframes[index].note = note
    }

    /// Removes a keyframe and closes the gap it leaves: everything after it moves earlier
    /// by the time it held, so the remaining timing is unchanged.
    mutating func remove(_ id: Keyframe.ID) {
        guard let index = index(of: id) else { return }
        let gap = index + 1 < keyframes.count ? keyframes[index + 1].time - keyframes[index].time : 0
        keyframes.remove(at: index)
        for later in keyframes.indices where later >= index {
            keyframes[later].time -= gap
        }
    }

    /// Moves a keyframe to a new position in the order. The moments on the timeline stay
    /// where they were; the keyframes trade places across them.
    mutating func move(_ id: Keyframe.ID, to index: Int) {
        guard let from = self.index(of: id) else { return }
        let times = keyframes.map(\.time)
        let keyframe = keyframes.remove(at: from)
        keyframes.insert(keyframe, at: min(max(index, 0), keyframes.count))
        for position in keyframes.indices {
            keyframes[position].time = times[position]
        }
    }

    /// The last keyframe clearly before `time`.
    func keyframe(before time: TimeInterval) -> Keyframe? {
        keyframes.last { $0.time < time - 0.01 }
    }

    /// The first keyframe clearly after `time`.
    func keyframe(after time: TimeInterval) -> Keyframe? {
        keyframes.first { $0.time > time + 0.01 }
    }

    func keyframe(_ id: Keyframe.ID?) -> Keyframe? {
        keyframes.first { $0.id == id }
    }

    func keyframe(near time: TimeInterval, tolerance: TimeInterval = 0.03) -> Keyframe? {
        keyframes.first { abs($0.time - time) <= tolerance }
    }

    /// True when both snapshots hold the same objects in the same poses, within small
    /// tolerances (a couple of millimeters, about a degree).
    static func posesMatch(_ a: [ObjectID: Transform], _ b: [ObjectID: Transform]) -> Bool {
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
    var keyframedObjectIDs: Set<ObjectID> {
        Set(keyframes.flatMap { $0.poses.keys })
    }

    /// The interpolated pose at `time` of every object visible then. Keyframed objects
    /// missing from the result are hidden at that time.
    func poses(at time: TimeInterval) -> [ObjectID: Transform] {
        // The keyframe in effect: the last one at or before `time`, else the first.
        guard let governing = keyframes.last(where: { $0.time <= time + 1e-6 }) ?? keyframes.first else { return [:] }

        var result: [ObjectID: Transform] = [:]
        for objectID in governing.poses.keys {
            let track = keyframes.compactMap { keyframe in keyframe.poses[objectID].map { (keyframe.time, $0, keyframe.holds) } }
            if let pose = Self.interpolate(track, at: time) { result[objectID] = pose }
        }
        return result
    }

    /// Each visible character's body pose at `time`, blended between keyframes the same
    /// way as positions (and held, where a keyframe holds).
    func characterPoses(at time: TimeInterval) -> [ObjectID: CharacterPose] {
        guard let governing = keyframes.last(where: { $0.time <= time + 1e-6 }) ?? keyframes.first else { return [:] }

        var result: [ObjectID: CharacterPose] = [:]
        for objectID in governing.characterPoses.keys where governing.poses[objectID] != nil {
            let track = keyframes.compactMap { keyframe in
                keyframe.characterPoses[objectID].map { (time: keyframe.time, pose: $0, holds: keyframe.holds) }
            }
            guard let (from, to, t) = Self.segment(of: track.map { ($0.time, $0.holds) }, at: time) else { continue }
            result[objectID] = track[from].pose.interpolated(to: track[to].pose, t)
        }
        return result
    }

    /// Removes a deleted object from every keyframe.
    /// - Returns: The keyframes that contained it.
    mutating func removeObject(_ objectID: ObjectID) -> [Keyframe.ID] {
        var changed: [Keyframe.ID] = []
        for index in keyframes.indices where keyframes[index].poses[objectID] != nil {
            keyframes[index].poses[objectID] = nil
            keyframes[index].characterPoses[objectID] = nil
            changed.append(keyframes[index].id)
        }
        return changed
    }

    /// Which two entries of a track `time` falls between, and how far along (eased).
    /// A holding entry stays put until the next one.
    private static func segment(of track: [(time: TimeInterval, holds: Bool)],
                                at time: TimeInterval) -> (from: Int, to: Int, t: Float)? {
        guard let first = track.first, let last = track.last else { return nil }
        if time <= first.time { return (0, 0, 0) }
        if time >= last.time { return (track.count - 1, track.count - 1, 0) }
        guard let next = track.firstIndex(where: { $0.time > time }), next > 0 else { return (track.count - 1, track.count - 1, 0) }
        let from = track[next - 1]
        if from.holds { return (next - 1, next - 1, 0) }
        let linear = Float((time - from.time) / (track[next].time - from.time))
        return (next - 1, next, linear * linear * (3 - 2 * linear)) // smoothstep: ease in and out of each pose
    }

    private static func interpolate(_ track: [(time: TimeInterval, pose: Transform, holds: Bool)],
                                    at time: TimeInterval) -> Transform? {
        guard let (fromIndex, toIndex, eased) = segment(of: track.map { ($0.time, $0.holds) }, at: time) else { return nil }
        let from = track[fromIndex].pose, to = track[toIndex].pose
        // simd_slerp takes the shortest arc, so a turn never spins the long way around.
        return Transform(
            scale: mix(from.scale, to.scale, t: eased),
            rotation: simd_slerp(from.rotation, to.rotation, eased),
            translation: mix(from.translation, to.translation, t: eased)
        )
    }
}
