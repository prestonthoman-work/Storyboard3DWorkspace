//
//  ObjectTapArbiter.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// Tells a deliberate double-tap on an object apart from grabbing it.
///
/// On the headset every pinch on an object starts a system manipulation, and the release of
/// a short, small pinch is also reported as a tap. Counting taps alone (as a two-tap gesture
/// does) turns "let go, then quickly grab again" into a double-tap, and a drag that barely
/// moves into a tap. So the scene reports each pinch's travel and duration here, and taps
/// are judged against them:
///
/// - A pinch that travels more than `dragDistance`, resizes the object, or lasts longer than
///   `maxTapDuration` is a grab. Its release is not a tap, and it cancels any first tap.
/// - A pinch that starts within `regrabWindow` of letting go of a drag is a re-grab. It
///   selects like any tap but can't begin a double-tap.
/// - Two taps on the same object within `doubleTapInterval`, with no grab between, are a
///   double-tap.
struct ObjectTapArbiter {
    /// Hand travel (meters, at the object) that turns a pinch into a drag. Small enough that
    /// a nudge counts as a drag, large enough to ignore the tremor of a held pinch.
    static let dragDistance: Float = 0.006
    /// A two-handed resize this large (as a fraction) is a grab, too.
    static let scaleChange: Float = 0.03
    /// Longer than this and a pinch is a hold, not a tap.
    static let maxTapDuration: TimeInterval = 0.45
    /// The most time between the two taps of a double-tap.
    static let doubleTapInterval: TimeInterval = 0.4
    /// A pinch starting this soon after a drag ends is taken as grabbing again.
    static let regrabWindow: TimeInterval = 0.35

    enum TapKind: Equatable {
        /// Select the object.
        case single
        /// Select the object and change its color.
        case double
        /// The release of a grab: nothing more to do (the grab already selected it).
        case grabRelease
    }

    private struct Pinch {
        var object: ObjectID
        var start: Date
        var startPosition: SIMD3<Float>
        var startScale: Float
        var end: Date?
        var isDrag = false
        /// Began right after letting go of a drag.
        var isRegrab = false

        func duration(at now: Date) -> TimeInterval { (end ?? now).timeIntervalSince(start) }
    }

    private var pinch: Pinch?
    private var lastDragEnd: Date?
    /// A first tap waiting for a second.
    private var pendingTap: (object: ObjectID, time: Date)?

    /// Whether the current pinch has become a drag.
    var isDragging: Bool { pinch.map { $0.end == nil && $0.isDrag } ?? false }

    mutating func pinchBegan(on object: ObjectID, at time: Date, position: SIMD3<Float>, scale: Float) {
        let isRegrab = lastDragEnd.map { time.timeIntervalSince($0) < Self.regrabWindow } ?? false
        pinch = Pinch(object: object, start: time, startPosition: position, startScale: max(scale, 1e-6),
                      isRegrab: isRegrab)
    }

    /// The object moved in the hand. Returns true the moment the pinch becomes a drag.
    @discardableResult
    mutating func pinchMoved(on object: ObjectID, position: SIMD3<Float>, scale: Float) -> Bool {
        guard var current = pinch, current.object == object, current.end == nil, !current.isDrag else { return false }
        let travel = simd_distance(position, current.startPosition)
        let resize = abs(scale / current.startScale - 1)
        guard travel > Self.dragDistance || resize > Self.scaleChange else { return false }
        current.isDrag = true
        pinch = current
        // Dragging means this wasn't the second half of a double-tap, or the first.
        pendingTap = nil
        return true
    }

    mutating func pinchEnded(on object: ObjectID, at time: Date) {
        guard var current = pinch, current.object == object, current.end == nil else { return }
        current.end = time
        if current.duration(at: time) > Self.maxTapDuration { current.isDrag = true }
        if current.isDrag {
            lastDragEnd = time
            pendingTap = nil
        }
        pinch = current
    }

    /// A tap was recognized on `object`. Taps arrive on release, just before or after the
    /// pinch that made them ends.
    mutating func tap(on object: ObjectID, at time: Date) -> TapKind {
        if let current = pinch, current.object == object {
            if current.isDrag || current.duration(at: time) > Self.maxTapDuration {
                pendingTap = nil
                return .grabRelease
            }
            if current.isRegrab {
                pendingTap = nil
                return .single
            }
        }
        if let pending = pendingTap, pending.object == object,
           time.timeIntervalSince(pending.time) <= Self.doubleTapInterval,
           lastDragEnd.map({ $0 < pending.time }) ?? true {
            pendingTap = nil
            return .double
        }
        pendingTap = (object, time)
        return .single
    }

    /// Forget everything, such as when the selection is cleared from the panel.
    mutating func reset() {
        pinch = nil
        lastDragEnd = nil
        pendingTap = nil
    }
}
