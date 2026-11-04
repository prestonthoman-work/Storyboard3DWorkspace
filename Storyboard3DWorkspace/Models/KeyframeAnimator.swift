//
//  KeyframeAnimator.swift
//  Storyboard3DWorkspace
//

import RealityKit
import SwiftUI

/// Records keyframes from an entity's transform and plays them back onto it.
@Observable
final class KeyframeAnimator {
    private(set) var timeline = KeyframeTimeline()
    private(set) var playhead: TimeInterval = 0
    private(set) var selectedKeyframeID: Keyframe.ID?
    private(set) var isPlaying = false

    @ObservationIgnored private let target: Entity
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    init(target: Entity) {
        self.target = target
    }

    var selectedKeyframe: Keyframe? { timeline.keyframe(selectedKeyframeID) }

    func selectedIndex(of keyframe: Keyframe) -> Int? {
        timeline.keyframes.firstIndex { $0.id == keyframe.id }
    }

    // MARK: Editing

    func addKeyframe() {
        pause()
        let keyframe = timeline.append(target.transform)
        selectedKeyframeID = keyframe.id
        playhead = keyframe.time
    }

    func updateSelectedKeyframe() {
        guard let id = selectedKeyframeID else { return }
        timeline.update(id, with: target.transform)
    }

    func deleteSelectedKeyframe() {
        guard let id = selectedKeyframeID else { return }
        pause()
        timeline.remove(id)
        selectedKeyframeID = nil
        playhead = min(playhead, timeline.duration)
        applyPlayhead()
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
        guard let transform = timeline.transform(at: playhead) else { return }
        target.transform = transform
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
