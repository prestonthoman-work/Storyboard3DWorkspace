//
//  KeyframeTimeline.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit
import simd

struct Keyframe: Identifiable, Equatable {
    let id = UUID()
    var time: TimeInterval
    /// The model's position, rotation, and scale at this keyframe.
    var transform: Transform
}

/// An ordered list of evenly spaced keyframes, with eased interpolation between them.
struct KeyframeTimeline {
    static let spacing: TimeInterval = 1

    private(set) var keyframes: [Keyframe] = []

    var duration: TimeInterval { keyframes.last?.time ?? 0 }
    var canPlay: Bool { keyframes.count >= 2 }

    @discardableResult
    mutating func append(_ transform: Transform) -> Keyframe {
        let keyframe = Keyframe(time: keyframes.isEmpty ? 0 : duration + Self.spacing, transform: transform)
        keyframes.append(keyframe)
        return keyframe
    }

    mutating func update(_ id: Keyframe.ID, with transform: Transform) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        keyframes[index].transform = transform
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

    func transform(at time: TimeInterval) -> Transform? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.transform }
        if time >= last.time { return last.transform }

        guard let nextIndex = keyframes.firstIndex(where: { $0.time > time }), nextIndex > 0 else {
            return last.transform
        }
        let from = keyframes[nextIndex - 1]
        let to = keyframes[nextIndex]
        let linear = Float((time - from.time) / (to.time - from.time))
        let eased = linear * linear * (3 - 2 * linear) // smoothstep: ease in and out of each pose

        return Transform(
            scale: mix(from.transform.scale, to.transform.scale, t: eased),
            rotation: simd_slerp(from.transform.rotation, to.transform.rotation, eased),
            translation: mix(from.transform.translation, to.transform.translation, t: eased)
        )
    }
}
