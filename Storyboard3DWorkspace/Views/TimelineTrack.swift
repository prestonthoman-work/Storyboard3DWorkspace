//
//  TimelineTrack.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// A scrubbable track showing keyframes as diamonds and the playhead as a knob.
///
/// - Drag anywhere on the track to scrub. Near a keyframe, the playhead clicks onto it.
/// - Tap a diamond to jump to that keyframe.
/// - Drag a diamond sideways to change when it happens (the first one stays at 0).
struct TimelineTrack: View {
    enum Size {
        /// A slim track for the side panel.
        case compact
        /// A tall track with a ruler and numbered keyframes, for the timeline window.
        case large
    }

    @Environment(AppModel.self) private var appModel
    var size: Size = .compact

    /// The keyframe being dragged, if any.
    @State private var draggingID: Keyframe.ID?
    /// The track's scale is held still while a keyframe is dragged, so moving the last
    /// keyframe doesn't rescale the track under the person's hand.
    @State private var frozenDuration: TimeInterval?

    private var animator: KeyframeAnimator { appModel.animator }
    private var inset: CGFloat { size == .large ? 28 : 14 }
    private var diamondSize: CGFloat { size == .large ? 22 : 13 }
    /// How close (in points) the playhead has to come to a keyframe to click onto it.
    private let snapDistance: CGFloat = 14

    /// The span the track shows. The large track leaves room after the last keyframe so it
    /// can be dragged later.
    private var visibleDuration: TimeInterval {
        if let frozenDuration { return frozenDuration }
        let duration = max(animator.timeline.duration, 1)
        return size == .large ? duration + max(0.5, duration * 0.12) : duration
    }

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - inset * 2, 1)
            let trackY = size == .large ? geometry.size.height * 0.62 : geometry.size.height / 2
            let playheadX = x(for: animator.playhead, width: usableWidth)

            ZStack(alignment: .topLeading) {
                if size == .large {
                    ruler(width: usableWidth, height: geometry.size.height)
                }

                // Track and progress.
                Capsule()
                    .fill(.quaternary)
                    .frame(width: x(for: animator.timeline.duration, width: usableWidth) - inset + 6,
                           height: size == .large ? 8 : 6)
                    .position(x: (x(for: animator.timeline.duration, width: usableWidth) + inset) / 2, y: trackY)
                Capsule()
                    .fill(.tint)
                    .frame(width: max(playheadX - inset, 0), height: size == .large ? 8 : 6)
                    .position(x: inset + max(playheadX - inset, 0) / 2, y: trackY)

                // Playhead line (large) sits behind the diamonds so they stay easy to grab.
                if size == .large {
                    Rectangle()
                        .fill(.white.opacity(0.8))
                        .frame(width: 2, height: geometry.size.height - 18)
                        .position(x: playheadX, y: (geometry.size.height + 18) / 2)
                        .allowsHitTesting(false)
                }

                ForEach(Array(animator.timeline.keyframes.enumerated()), id: \.element.id) { index, keyframe in
                    diamond(keyframe, number: index + 1, width: usableWidth)
                        .position(x: x(for: keyframe.time, width: usableWidth), y: trackY)
                }

                Circle()
                    .fill(.white)
                    .frame(width: size == .large ? 16 : 20, height: size == .large ? 16 : 20)
                    .shadow(color: .black.opacity(0.25), radius: 3)
                    .position(x: playheadX, y: size == .large ? 12 : trackY)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .coordinateSpace(name: "track")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("track"))
                    .onChanged { value in
                        guard !animator.timeline.keyframes.isEmpty else { return }
                        let tolerance = TimeInterval(snapDistance / usableWidth) * visibleDuration
                        appModel.scrubTimeline(to: time(at: value.location.x, width: usableWidth),
                                               snapTolerance: tolerance)
                    }
            )
            .animation(.snappy(duration: 0.2), value: animator.timeline.keyframes.map(\.time))
        }
        .frame(height: size == .large ? 120 : 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline")
        .accessibilityValue(String(format: "%.1f of %.1f seconds", animator.playhead, animator.timeline.duration))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: appModel.stepKeyframe(forward: true)
            case .decrement: appModel.stepKeyframe(forward: false)
            @unknown default: break
            }
        }
    }

    // MARK: Pieces

    private func diamond(_ keyframe: Keyframe, number: Int, width: CGFloat) -> some View {
        let isSelected = keyframe.id == animator.selectedKeyframeID
        let isDragging = keyframe.id == draggingID
        let canRetime = number > 1

        return VStack(spacing: 4) {
            if size == .large {
                Text("\(number)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.white)
                .frame(width: diamondSize, height: diamondSize)
                .rotationEffect(.degrees(45))
                .overlay {
                    if isSelected {
                        Rectangle()
                            .strokeBorder(.white, lineWidth: 2)
                            .frame(width: diamondSize, height: diamondSize)
                            .rotationEffect(.degrees(45))
                    }
                }
                .scaleEffect(isDragging ? 1.3 : 1)
                .shadow(color: .black.opacity(0.3), radius: 2)
            if size == .large && isDragging {
                Text(keyframe.time.formatted(.number.precision(.fractionLength(1))) + " s")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
            }
        }
        // Generous target: easy to look at and pinch.
        .frame(width: size == .large ? 44 : 30, height: size == .large ? 74 : 40)
        .offset(y: size == .large ? -12 : 0)
        .contentShape(Rectangle())
        .hoverEffect(.lift)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("track"))
                .onChanged { value in
                    let moved = abs(value.location.x - value.startLocation.x)
                    guard canRetime, moved > 6 else { return }
                    if draggingID == nil {
                        frozenDuration = visibleDuration
                        draggingID = keyframe.id
                        appModel.beginRetimingKeyframe()
                    }
                    appModel.retimeKeyframe(keyframe.id, to: time(at: value.location.x, width: width, clamped: false))
                }
                .onEnded { _ in
                    if draggingID != nil {
                        appModel.endRetimingKeyframe()
                    } else {
                        appModel.selectKeyframe(keyframe)
                    }
                    draggingID = nil
                    frozenDuration = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Keyframe \(number), \(keyframe.time.formatted(.number.precision(.fractionLength(1)))) seconds")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { appModel.selectKeyframe(keyframe) }
    }

    /// Second marks along the top of the large track.
    private func ruler(width: CGFloat, height: CGFloat) -> some View {
        let seconds = Int(visibleDuration.rounded(.up))
        let labelEvery = max(1, seconds / 12)
        return ZStack(alignment: .topLeading) {
            ForEach(0...seconds, id: \.self) { second in
                let tickX = x(for: TimeInterval(second), width: width)
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 1, height: height - 30)
                    .position(x: tickX, y: 26 + (height - 30) / 2)
                if second % labelEvery == 0 {
                    Text("\(second)s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: tickX + 12, y: 30)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Geometry

    private func x(for time: TimeInterval, width: CGFloat) -> CGFloat {
        inset + CGFloat(time / visibleDuration) * width
    }

    private func time(at x: CGFloat, width: CGFloat, clamped: Bool = true) -> TimeInterval {
        let fraction = (x - inset) / width
        let time = TimeInterval(fraction) * visibleDuration
        return clamped ? min(max(time, 0), animator.timeline.duration) : max(time, 0)
    }
}

/// Play, step between keyframes, loop, and where the playhead is.
struct KeyframeTransport: View {
    @Environment(AppModel.self) private var appModel
    var showsShortcuts = false

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        @Bindable var animator = appModel.animator

        HStack(spacing: 10) {
            Button("Previous Keyframe", systemImage: "backward.end.fill") {
                appModel.stepKeyframe(forward: false)
            }
            .disabled(!animator.canStepBackward)
            .help("Go to the previous keyframe")
            .modifier(Shortcut(enabled: showsShortcuts, key: .leftArrow))

            Button(animator.isPlaying ? "Pause" : "Play",
                   systemImage: animator.isPlaying ? "pause.fill" : "play.fill") {
                animator.togglePlayback()
            }
            .disabled(!animator.timeline.canPlay)
            .help("Play the animation. Needs at least two keyframes.")
            .modifier(Shortcut(enabled: showsShortcuts, key: .space))

            Button("Next Keyframe", systemImage: "forward.end.fill") {
                appModel.stepKeyframe(forward: true)
            }
            .disabled(!animator.canStepForward)
            .help("Go to the next keyframe")
            .modifier(Shortcut(enabled: showsShortcuts, key: .rightArrow))

            Toggle(isOn: $animator.isLooping) {
                Label("Loop", systemImage: "repeat")
            }
            .toggleStyle(.button)
            .help("Play over and over")

            Text(String(format: "%.1f s / %.1f s", animator.playhead, animator.timeline.duration))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
    }

    private struct Shortcut: ViewModifier {
        let enabled: Bool
        let key: KeyEquivalent

        func body(content: Content) -> some View {
            if enabled {
                content.keyboardShortcut(key, modifiers: [])
            } else {
                content
            }
        }
    }
}

/// One line saying what an edit will do right now, so it's never a guess.
struct KeyframeStatusLine: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let (text, symbol, tint): (String, String, Color) = switch appModel.animator.position {
        case .empty:
            ("Arrange the scene, then add your first keyframe.", "plus.diamond", .secondary)
        case .playing:
            ("Playing. Pause or tap a keyframe to edit.", "play.fill", .secondary)
        case .onKeyframe(let number):
            ("Editing keyframe \(number). Changes save automatically.", "pencil.circle.fill", .green)
        case .between(let previous, let next):
            ("Between keyframes \(previous) and \(next). Moving something adds a keyframe here.", "diamond", .orange)
        }

        Label(text, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(tint)
            .lineLimit(2)
            .contentTransition(.opacity)
            .animation(.snappy, value: appModel.animator.position)
    }
}
