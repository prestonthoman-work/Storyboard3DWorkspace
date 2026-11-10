//
//  TimelineWindow.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// A wide window just for keyframes: transport controls, a large track whose diamonds can
/// be tapped and dragged, and the shots as a filmstrip. Opens with the Animate tab.
struct TimelineWindow: View {
    static let windowID = "timeline"

    @Environment(AppModel.self) private var appModel

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if animator.timeline.keyframes.isEmpty {
                emptyState
            } else {
                TimelineTrack(size: .large)
                    .padding(.vertical, 6)
                    .platter()
                ShotStrip(cardWidth: 168, showsTimesAndAdd: true)
                Spacer(minLength: 0)
                hints
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appModel.isTimelineWindowOpen = true }
        .onDisappear { appModel.isTimelineWindowOpen = false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerControls
            KeyframeStatusLine()
        }
    }

    private var headerControls: some View {
        HStack(alignment: .center, spacing: 20) {
            Text("Timeline")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            KeyframeTransport(showsShortcuts: true)

            HStack(spacing: 10) {
                if let selected = animator.selectedKeyframeID {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        withAnimation(.snappy) { appModel.duplicateKeyframe(selected) }
                    }
                    .labelStyle(.iconOnly)
                    .help("Copy this keyframe and put the copy right after it")

                    Button("Delete Keyframe", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) { appModel.deleteKeyframe(selected) }
                    }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Delete this keyframe. Its photos move to the library.")
                }

                AddKeyframeButton()
                    .keyboardShortcut("k", modifiers: [])
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var emptyState: some View {
        EmptyState(symbol: "diamond",
                   title: "No keyframes yet",
                   message: "A keyframe saves where everything is. Arrange the scene, add a keyframe, then move things and add another. Playback glides between them.") {
            AddKeyframeButton(title: "Add First Keyframe")
                .controlSize(.large)
        }
    }

    private var hints: some View {
        HStack(spacing: 18) {
            hint("hand.tap", "Tap to edit")
            hint("arrow.left.and.right", "Drag a diamond to retime")
            hint("wand.and.stars", "Edit between keyframes to add one")
            Spacer(minLength: 0)
            hint("keyboard", "Space · ← → · K")
        }
        .font(.footnote)
        .foregroundStyle(.tertiary)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .lineLimit(1)
    }
}

/// Adds a keyframe where the person is: after the selected one, at the playhead, or at the end.
struct AddKeyframeButton: View {
    @Environment(AppModel.self) private var appModel
    var title: String?

    var body: some View {
        Button {
            withAnimation(.snappy) { appModel.addKeyframe() }
        } label: {
            Label(title ?? label, systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .help("Save the scene as it is now into a new keyframe and select it")
    }

    private var label: String {
        switch appModel.animator.position {
        case .empty: "Add Keyframe"
        case .between: "Add Keyframe Here"
        case .onKeyframe: "Add Keyframe"
        case .playing: "Add Keyframe"
        }
    }
}
