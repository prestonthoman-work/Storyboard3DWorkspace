//
//  AnimatePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct AnimatePanel: View {
    @Environment(AppModel.self) private var appModel

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if animator.timeline.keyframes.isEmpty {
                Text("Pose the model, then add a keyframe. Pose it again and add another, and playback moves smoothly between them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                transport
                keyframeChips
            }

            Spacer(minLength: 0)

            editActions
        }
    }

    private var transport: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Button {
                    animator.togglePlayback()
                } label: {
                    Label(animator.isPlaying ? "Pause" : "Play",
                          systemImage: animator.isPlaying ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonBorderShape(.circle)
                .disabled(!animator.timeline.canPlay)
                .help("Play the animation. Needs at least two keyframes.")

                Text(String(format: "%.1f s / %.1f s", animator.playhead, animator.timeline.duration))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TimelineTrack(
                duration: animator.timeline.duration,
                playhead: animator.playhead,
                keyframes: animator.timeline.keyframes,
                selectedKeyframeID: animator.selectedKeyframeID,
                onScrub: animator.scrub(to:)
            )
        }
    }

    private var keyframeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(animator.timeline.keyframes.enumerated()), id: \.element.id) { index, keyframe in
                    let isSelected = keyframe.id == animator.selectedKeyframeID
                    Button("\(index + 1)") { animator.select(keyframe) }
                        .buttonBorderShape(.circle)
                        .tint(isSelected ? .accentColor : nil)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Keyframe \(index + 1)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var editActions: some View {
        HStack(spacing: 12) {
            Button {
                animator.addKeyframe()
            } label: {
                Label("Add Keyframe", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            if animator.selectedKeyframe != nil {
                Button("Update", systemImage: "arrow.triangle.2.circlepath") {
                    animator.updateSelectedKeyframe()
                }
                .help("Replace the selected keyframe with the model's current pose")

                Button("Delete", systemImage: "trash", role: .destructive) {
                    animator.deleteSelectedKeyframe()
                }
                .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
    }
}
