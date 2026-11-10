//
//  ShotList.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Every shot (keyframe) in order as a filmstrip: its primary photo, number, and notes.
/// Tap to select, drag onto another shot to reorder, or use the context menu.
struct ShotList: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PanelSection("Storyboard", symbol: "rectangle.split.3x1") {
            Button {
                openWindow(id: StoryboardViewer.windowID)
            } label: {
                Label("Play", systemImage: "play.rectangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appModel.slideshowCoverage.withPhoto == 0)
            .help("Watch the storyboard full screen, shot by shot")
        } content: {
            ShotStrip(cardWidth: 136)
        }
    }
}

/// The shots as a horizontal filmstrip. Tap to select, drag onto another shot to reorder,
/// or open the context menu to duplicate, move, or delete.
struct ShotStrip: View {
    @Environment(AppModel.self) private var appModel
    var cardWidth: CGFloat = 136
    /// Show each shot's time and an Add card at the end.
    var showsTimesAndAdd = false

    var body: some View {
        let keyframes = appModel.animator.timeline.keyframes

        ScrollViewReader { proxy in
            HorizontalStrip(spacing: 12) {
                    ForEach(Array(keyframes.enumerated()), id: \.element.id) { index, keyframe in
                        ShotCard(
                            number: index + 1,
                            time: showsTimesAndAdd ? keyframe.time : nil,
                            primary: appModel.photos.primaryPhoto(for: keyframe.id),
                            photoCount: appModel.photos.photos(for: keyframe.id).count,
                            note: keyframe.note,
                            shotType: keyframe.shotType,
                            isSelected: keyframe.id == appModel.animator.selectedKeyframeID,
                            width: cardWidth
                        ) {
                            appModel.selectKeyframe(keyframe)
                        }
                        .id(keyframe.id)
                        .draggable(keyframe.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                            withAnimation(.snappy) { appModel.moveKeyframe(id, to: index) }
                            return true
                        }
                        .contextMenu {
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                withAnimation(.snappy) { appModel.duplicateKeyframe(keyframe.id) }
                            }
                            Button("Move Earlier", systemImage: "arrow.left") {
                                withAnimation(.snappy) { appModel.moveKeyframe(keyframe.id, to: index - 1) }
                            }
                            .disabled(index == 0)
                            Button("Move Later", systemImage: "arrow.right") {
                                withAnimation(.snappy) { appModel.moveKeyframe(keyframe.id, to: index + 1) }
                            }
                            .disabled(index == keyframes.count - 1)
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(.snappy) { appModel.deleteKeyframe(keyframe.id) }
                            }
                        }
                    }

                    if showsTimesAndAdd {
                        AddShotCard(width: cardWidth) {
                            withAnimation(.snappy) { appModel.addKeyframe() }
                        }
                    }
            }
            // Keep the selected shot in view as the playhead moves between keyframes.
            .onChange(of: appModel.animator.selectedKeyframeID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// A dashed placeholder at the end of the filmstrip that adds a keyframe.
private struct AddShotCard: View {
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title2)
                Text("Add Keyframe")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(width: width, height: width * 9 / 16)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .help("Add a keyframe after the selected one, holding the scene as it is now")
    }
}

struct ShotCard: View {
    let number: Int
    var time: TimeInterval? = nil
    let primary: CapturedPhoto?
    let photoCount: Int
    let note: String
    var shotType: ShotType? = nil
    let isSelected: Bool
    var width: CGFloat = 136
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.06))
                        if let primary {
                            Image(uiImage: primary.thumbnail)
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        } else {
                            Image(systemName: "camera")
                                .font(.title3.weight(.light))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: width, height: width * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(time.map { String(format: "%02d · %.1fs", number, $0) } ?? String(format: "%02d", number))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if photoCount > 1 {
                        Label("\(photoCount)", systemImage: "photo.stack")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let shotType {
                        Text(shotType.abbreviation)
                            .font(.caption2.weight(.bold).monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.85), in: Capsule())
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 3)
                }

                Text(note.isEmpty ? "No notes" : note)
                    .font(.caption)
                    .foregroundStyle(note.isEmpty ? .tertiary : .secondary)
                    .lineLimit(2, reservesSpace: true)
                    .frame(width: width, alignment: .leading)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("Shot \(number)\(shotType.map { ", \($0.name)" } ?? "")\(note.isEmpty ? "" : ", \(note)")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
