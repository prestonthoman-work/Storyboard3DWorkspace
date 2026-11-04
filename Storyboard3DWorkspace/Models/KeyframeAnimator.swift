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
        timeline.keyframes.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Replaces the whole timeline (undo, or loading a saved project) without moving any
    /// objects: their poses are restored separately.
    func restore(_ keyframes: [Keyframe], selecting selectedID: Keyframe.ID?) {
        pause()
        timeline = KeyframeTimeline(keyframes: keyframes)
        selectedKeyframeID = timeline.keyframe(selectedID)?.id
        playhead = selectedKeyframe?.time ?? 0
    }

    // MARK: Editing

    func addKeyframe() {
        pause()
        let keyframe = timeline.append(scene.currentPoses())
        selectedKeyframeID = keyframe.id
        playhead = keyframe.time
    }

    /// Auto-save: writes the current arrangement into the selected keyframe.
    /// - Returns: The keyframe's ID if its poses actually changed.
    @discardableResult
    func saveSceneToSelectedKeyframe() -> Keyframe.ID? {
        guard !isPlaying, let keyframe = selectedKeyframe else { return nil }
        let poses = scene.currentPoses()
        guard !KeyframeTimeline.posesMatch(keyframe.poses, poses) else { return nil }
        timeline.update(keyframe.id, with: poses)
        return keyframe.id
    }

    /// A deleted object leaves every keyframe.
    /// - Returns: The keyframes that contained it.
    func removeObject(_ objectID: ObjectID) -> [Keyframe.ID] {
        timeline.removeObject(objectID)
    }

    /// - Returns: The deleted keyframe's ID.
    @discardableResult
    func deleteSelectedKeyframe() -> Keyframe.ID? {
        guard let id = selectedKeyframeID else { return nil }
        pause()
        timeline.remove(id)
        selectedKeyframeID = nil
        playhead = min(playhead, timeline.duration)
        applyPlayhead()
        return id
    }

    func select(_ keyframe: Keyframe) {
        pause()
        selectedKeyframeID = keyframe.id
        playhead = keyframe.time
        applyPlayhead()
    }

    func scrub(to time: TimeInterval) {
        pause()
        playhead = min(max(time, 0), timeline.duration)
        selectedKeyframeID = timeline.keyframe(near: playhead)?.id
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

                self.playhead = min(self.playhead + elapsed.timeInterval, self.timeline.duration)
                self.applyPlayhead()
                if self.playhead >= self.timeline.duration {
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
