//
//  TimelineTrack.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// A scrubbable track showing keyframes as diamonds and the playhead as a knob.
struct TimelineTrack: View {
    let duration: TimeInterval
    let playhead: TimeInterval
    let keyframes: [Keyframe]
    let selectedKeyframeID: Keyframe.ID?
    let onScrub: (TimeInterval) -> Void

    private let inset: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - inset * 2, 1)
            let midY = geometry.size.height / 2
            let playheadX = xPosition(for: playhead, width: usableWidth)

            ZStack {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: usableWidth, height: 6)
                    .position(x: geometry.size.width / 2, y: midY)

                Capsule()
                    .fill(.tint)
                    .frame(width: max(playheadX - inset, 0), height: 6)
                    .position(x: inset + max(playheadX - inset, 0) / 2, y: midY)

                ForEach(keyframes) { keyframe in
                    Rectangle()
                        .fill(keyframe.id == selectedKeyframeID ? Color.accentColor : Color.white)
                        .frame(width: 11, height: 11)
                        .rotationEffect(.degrees(45))
                        .position(x: xPosition(for: keyframe.time, width: usableWidth), y: midY)
                }

                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.25), radius: 3)
                    .position(x: playheadX, y: midY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        let fraction = min(max((value.location.x - inset) / usableWidth, 0), 1)
                        onScrub(fraction * duration)
                    }
            )
        }
        .frame(height: 40)
        .hoverEffect(.highlight)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue(String(format: "%.1f of %.1f seconds", playhead, duration))
        .accessibilityAdjustableAction { direction in
            let step = KeyframeTimeline.spacing / 4
            switch direction {
            case .increment: onScrub(min(playhead + step, duration))
            case .decrement: onScrub(max(playhead - step, 0))
            @unknown default: break
            }
        }
    }

    private func xPosition(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return inset }
        return inset + CGFloat(time / duration) * width
    }
}
