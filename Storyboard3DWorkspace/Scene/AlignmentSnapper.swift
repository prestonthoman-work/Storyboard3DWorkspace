//
//  AlignmentSnapper.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// Gentle position snapping: lines a moving object's center up with nearby objects along
/// the base's two axes, without ever touching its rotation.
///
/// While the object is in your hand nothing is pulled; a guide previews the alignment it
/// would take, and it's applied when you let go. That keeps hand tremor from flicking the
/// object between targets, and moving away from a guide is all it takes to place freely.
///
/// - A target is offered only within `captureDistance`, and kept until you're past
///   `releaseDistance`, so a hand hovering at the edge doesn't flicker the guide.
/// - A closer target takes over only when it's closer by `switchMargin`, so two nearby
///   targets don't trade places with every tremor.
/// - Targets the object was already lined up with when you picked it up are left out
///   until it's moved `rearmDistance` away, so nudging an aligned object a few
///   millimeters doesn't snap it straight back.
struct AlignmentSnapper {
    static let captureDistance: Float = 0.004
    static let releaseDistance: Float = 0.007
    static let switchMargin: Float = 0.0015
    static let rearmDistance: Float = 0.015
    /// Lined up this closely at pickup counts as already aligned.
    static let alignedTolerance: Float = 0.0008

    /// One of the base's horizontal axes.
    enum Axis: Int, CaseIterable {
        case x = 0
        case z = 2
    }

    struct Target: Equatable {
        var object: ObjectID
        /// The coordinate the moving object would take on this axis.
        var value: Float
    }

    /// Where other objects' centers are, on the base: (x, z).
    typealias Neighbor = (id: ObjectID, position: SIMD2<Float>)

    private(set) var targets: [Axis: Target] = [:]
    private var suppressed: [Axis: Set<ObjectID>] = [:]

    /// Starts a move from `position` (x, z), noting what the object is already aligned with.
    mutating func begin(at position: SIMD2<Float>, neighbors: [Neighbor]) {
        targets = [:]
        suppressed = [:]
        for axis in Axis.allCases {
            let ids = neighbors.filter { abs(Self.coordinate($0.position, axis) - Self.coordinate(position, axis)) < Self.alignedTolerance }
                .map(\.id)
            suppressed[axis] = Set(ids)
        }
    }

    /// Updates the preview for the object's unsnapped position. Returns the targets it would
    /// snap to if released now.
    @discardableResult
    mutating func update(position: SIMD2<Float>, neighbors: [Neighbor]) -> [Axis: Target] {
        for axis in Axis.allCases {
            let own = Self.coordinate(position, axis)
            let distances = neighbors.map { (id: $0.id, value: Self.coordinate($0.position, axis),
                                             distance: abs(Self.coordinate($0.position, axis) - own)) }

            // Re-arm targets left behind at pickup once the object has clearly moved away.
            if var held = suppressed[axis] {
                held = held.filter { id in distances.first { $0.id == id }.map { $0.distance < Self.rearmDistance } ?? false }
                suppressed[axis] = held
            }
            let eligible = distances.filter { !(suppressed[axis]?.contains($0.id) ?? false) }
            let nearest = eligible.min { $0.distance < $1.distance }

            if let current = targets[axis], let still = eligible.first(where: { $0.id == current.object }),
               still.distance <= Self.releaseDistance {
                // Keep the current target unless another is clearly closer and within reach.
                if let nearest, nearest.id != current.object, nearest.distance <= Self.captureDistance,
                   nearest.distance + Self.switchMargin < still.distance {
                    targets[axis] = Target(object: nearest.id, value: nearest.value)
                } else {
                    targets[axis] = Target(object: current.object, value: still.value)
                }
            } else if let nearest, nearest.distance <= Self.captureDistance {
                targets[axis] = Target(object: nearest.id, value: nearest.value)
            } else {
                targets[axis] = nil
            }
        }
        return targets
    }

    /// Where the object lands if let go at `position` now.
    func snapped(_ position: SIMD2<Float>) -> SIMD2<Float> {
        var result = position
        if let x = targets[.x] { result.x = x.value }
        if let z = targets[.z] { result.y = z.value }
        return result
    }

    mutating func end() {
        targets = [:]
        suppressed = [:]
    }

    private static func coordinate(_ position: SIMD2<Float>, _ axis: Axis) -> Float {
        axis == .x ? position.x : position.y
    }
}

/// Soft rotation detents for the turn and tilt rings: the angle clicks onto a 15° step when
/// it's within `capture` of one, and moves freely in between, so a precise angle is never
/// fought. Separate from position snapping, and only ever used by the rings.
enum RotationDetent {
    static let step: Float = .pi / 12
    static let capture: Float = 3.5 * .pi / 180

    /// `angle` (radians), pulled onto the nearest step when close. Also returns that step's
    /// index when it snapped.
    static func apply(_ angle: Float) -> (angle: Float, step: Int?) {
        let index = (angle / step).rounded()
        let snappedAngle = index * step
        guard abs(angle - snappedAngle) <= capture else { return (angle, nil) }
        return (snappedAngle, Int(index))
    }
}
