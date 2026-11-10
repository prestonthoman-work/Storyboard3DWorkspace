//
//  KeyframeAnimator.swift
//  Storyboard3DWorkspace
//

import RealityKit
import SwiftUI

/// Records snapshots of every placed object's pose and plays them back.
@Observable
final class KeyframeAnimator {
    private(set) var timeline = KeyframeTimeline()
    private(set) var playhead: TimeInterval = 0
    private(set) var selectedKeyframeID: Keyframe.ID?
    private(set) var isPlaying = false {
        // Keyframes drive object heights during playback; gravity resumes when it stops.
        didSet { ObjectGravitySystem.isFallingPaused = isPlaying }
    }

    @ObservationIgnored private let scene: WorkspaceScene
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    init(scene: WorkspaceScene) {
        self.scene = scene
    }

    var selectedKeyframe: Keyframe? { timeline.keyframe(selectedKeyframeID) }

    /// 1-based position of a keyframe in the timeline, for display.
    func number(of id: Keyframe.ID) -> Int? {
        timeline.index(of: id).map { $0 + 1 }
    }

    /// Replaces the whole timeline (undo, or loading a saved project) without moving any
    /// objects: their poses are restored separately.
    func restore(_ keyframes: [Keyframe], selecting selectedID: Keyframe.ID?) {
        pause()
        timeline = KeyframeTimeline(keyframes: keyframes)
        selectedKeyframeID = timeline.keyframe(selectedID)?.id
        playhead = selectedKeyframe?.time ?? 0
    }

    /// Where the playhead sits relative to the keyframes, for status lines.
    enum Position: Equatable {
        case empty
        case playing
        case onKeyframe(number: Int)
        case between(previous: Int, next: Int)
    }

    var position: Position {
        if timeline.keyframes.isEmpty { return .empty }
        if isPlaying { return .playing }
        if let id = selectedKeyframeID, let number = number(of: id) { return .onKeyframe(number: number) }
        let previous = timeline.keyframes.lastIndex { $0.time <= playhead } ?? 0
        return .between(previous: previous + 1, next: min(previous + 2, timeline.keyframes.count))
    }

    /// Playback starts over at the end instead of stopping.
    var isLooping = false

    // MARK: Editing

    /// Adds a keyframe holding the scene as it is now, right where the person is looking:
    /// after the selected keyframe, at the playhead when it's between keyframes, or at the end.
    @discardableResult
    func addKeyframe() -> Keyframe {
        pause()
        let poses = scene.currentPoses()
        let keyframe: Keyframe
        if let selected = selectedKeyframeID, let inserted = timeline.insert(poses, after: selected) {
            keyframe = inserted
        } else if let inserted = timeline.insert(poses, at: playhead) {
            keyframe = inserted
        } else if let previous = timeline.keyframes.last(where: { $0.time <= playhead }),
                  let inserted = timeline.insert(poses, after: previous.id) {
            keyframe = inserted
        } else {
            keyframe = timeline.append(poses)
        }
        selectedKeyframeID = keyframe.id
        playhead = keyframe.time
        return keyframe
    }

    /// Auto-save: writes the current arrangement into the selected keyframe. With the
    /// playhead between keyframes, an edit adds a new keyframe there instead, so no change
    /// is ever lost.
    /// - Returns: The keyframe's ID if its poses actually changed or it was added.
    @discardableResult
    func saveSceneToSelectedKeyframe() -> Keyframe.ID? {
        guard !isPlaying else { return nil }
        let poses = scene.currentPoses()
        guard let keyframe = selectedKeyframe else {
            // What the timeline shows here, plus objects that aren't animated at all.
            let keyframed = timeline.keyframedObjectIDs
            let expected = timeline.poses(at: playhead).merging(poses.filter { !keyframed.contains($0.key) }) { a, _ in a }
            guard !KeyframeTimeline.posesMatch(expected, poses),
                  let inserted = timeline.insert(poses, at: playhead) else { return nil }
            selectedKeyframeID = inserted.id
            return inserted.id
        }
        guard !KeyframeTimeline.posesMatch(keyframe.poses, poses) else { return nil }
        timeline.update(keyframe.id, with: poses)
        return keyframe.id
    }

    func setNote(_ note: String, for id: Keyframe.ID) {
        timeline.setNote(note, for: id)
    }

    func setShotType(_ shotType: ShotType?, for id: Keyframe.ID) {
        timeline.setShotType(shotType, for: id)
    }

    /// A deleted object leaves every keyframe.
    /// - Returns: The keyframes that contained it.
    func removeObject(_ objectID: ObjectID) -> [Keyframe.ID] {
        timeline.removeObject(objectID)
    }

    /// Deletes a keyframe and selects its neighbor, so editing carries on smoothly.
    /// - Returns: True if it was deleted.
    @discardableResult
    func deleteKeyframe(_ id: Keyframe.ID) -> Bool {
        guard let index = timeline.index(of: id) else { return false }
        pause()
        let wasSelected = id == selectedKeyframeID
        timeline.remove(id)
        if wasSelected || selectedKeyframe == nil {
            let neighbor = timeline.keyframes.indices.contains(index - 1) ? index - 1 : 0
            selectedKeyframeID = timeline.keyframes.indices.contains(neighbor) ? timeline.keyframes[neighbor].id : nil
        }
        playhead = selectedKeyframe?.time ?? min(playhead, timeline.duration)
        applyPlayhead()
        return true
    }

    /// - Returns: The deleted keyframe's ID.
    @discardableResult
    func deleteSelectedKeyframe() -> Keyframe.ID? {
        guard let id = selectedKeyframeID, deleteKeyframe(id) else { return nil }
        return id
    }

    /// Adds a copy of a keyframe right after it and selects the copy.
    @discardableResult
    func duplicateKeyframe(_ id: Keyframe.ID) -> Keyframe? {
        pause()
        guard let copy = timeline.duplicate(id) else { return nil }
        selectedKeyframeID = copy.id
        playhead = copy.time
        applyPlayhead()
        return copy
    }

    /// Drags a keyframe to a new time. It stays selected and the playhead follows it.
    @discardableResult
    func retimeKeyframe(_ id: Keyframe.ID, to time: TimeInterval) -> Bool {
        pause()
        guard timeline.retime(id, to: time), let keyframe = timeline.keyframe(id) else { return false }
        selectedKeyframeID = id
        playhead = keyframe.time
        return true
    }

    func moveKeyframe(_ id: Keyframe.ID, to index: Int) {
        pause()
        timeline.move(id, to: index)
        if let selected = selectedKeyframe { playhead = selected.time }
        applyPlayhead()
    }

    func select(_ keyframe: Keyframe) {
        pause()
        selectedKeyframeID = keyframe.id
        playhead = keyframe.time
        applyPlayhead()
    }

    /// Jumps to the keyframe before or after the playhead. Nothing happens at either end.
    func step(forward: Bool) {
        let target = forward ? timeline.keyframe(after: playhead) : timeline.keyframe(before: playhead)
        if let target { select(target) }
    }

    var canStepBackward: Bool { timeline.keyframe(before: playhead) != nil }
    var canStepForward: Bool { timeline.keyframe(after: playhead) != nil }

    /// Moves the playhead. Within `snapTolerance` of a keyframe, it clicks onto it.
    func scrub(to time: TimeInterval, snapTolerance: TimeInterval = 0.03) {
        pause()
        let clamped = min(max(time, 0), timeline.duration)
        let nearest = timeline.keyframes.min { abs($0.time - clamped) < abs($1.time - clamped) }
        if let nearest, abs(nearest.time - clamped) <= snapTolerance {
            playhead = nearest.time
            selectedKeyframeID = nearest.id
        } else {
            playhead = clamped
            selectedKeyframeID = nil
        }
        applyPlayhead()
    }

    // MARK: Playback

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard timeline.canPlay, !isPlaying else { return }
        if playhead >= timeline.duration - 0.001 { playhead = 0 }
        selectedKeyframeID = nil
        isPlaying = true

        playbackTask = Task { [weak self] in
            let clock = ContinuousClock()
            var lastTick = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(11))
                guard let self, !Task.isCancelled else { return }
                let now = clock.now
                let elapsed = now - lastTick
                lastTick = now

                let duration = self.timeline.duration
                var next = self.playhead + elapsed.timeInterval
                if next >= duration, self.isLooping, duration > 0 {
                    next = next.truncatingRemainder(dividingBy: duration)
                }
                self.playhead = min(next, duration)
                self.applyPlayhead()
                if self.playhead >= duration {
                    self.selectedKeyframeID = self.timeline.keyframes.last?.id
                    break
                }
            }
            // A cancelled task must not clear the flag: a newer playback may already be running.
            if !Task.isCancelled { self?.isPlaying = false }
        }
    }

    func pause() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func applyPlayhead() {
        scene.apply(timeline.poses(at: playhead), keyframedObjects: timeline.keyframedObjectIDs)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
