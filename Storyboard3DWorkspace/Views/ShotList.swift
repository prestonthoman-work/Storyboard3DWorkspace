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
        let keyframes = appModel.animator.timeline.keyframes

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shot List")
                    .font(.headline)
                Text("\(keyframes.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openWindow(id: StoryboardViewer.windowID)
                } label: {
                    Label("Play Storyboard", systemImage: "play.rectangle")
                }
                .buttonStyle(.bordered)
                .disabled(appModel.slideshowCoverage.withPhoto == 0)
                .help("Watch the storyboard full screen, shot by shot")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(keyframes.enumerated()), id: \.element.id) { index, keyframe in
                        ShotCard(
                            number: index + 1,
                            primary: appModel.photos.primaryPhoto(for: keyframe.id),
                            photoCount: appModel.photos.photos(for: keyframe.id).count,
                            note: keyframe.note,
                            isSelected: keyframe.id == appModel.animator.selectedKeyframeID
                        ) {
                            appModel.selectKeyframe(keyframe)
                        }
                        .draggable(keyframe.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                            withAnimation(.snappy) { appModel.moveKeyframe(id, to: index) }
                            return true
                        }
                        .contextMenu {
                            Button("Move Earlier", systemImage: "arrow.left") {
                                withAnimation(.snappy) { appModel.moveKeyframe(keyframe.id, to: index - 1) }
                            }
                            .disabled(index == 0)
                            Button("Move Later", systemImage: "arrow.right") {
                                withAnimation(.snappy) { appModel.moveKeyframe(keyframe.id, to: index + 1) }
                            }
                            .disabled(index == keyframes.count - 1)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

private struct ShotCard: View {
    let number: Int
    let primary: CapturedPhoto?
    let photoCount: Int
    let note: String
    let isSelected: Bool
    let action: () -> Void

    private let width: CGFloat = 136

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.quaternary)
                        if let primary {
                            Image(uiImage: primary.thumbnail)
                                .resizable()
                                .aspectRatio(16 / 9, contentMode: .fill)
                        } else {
                            Image(systemName: "camera")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: width, height: width * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(String(format: "%02d", number))
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
        .accessibilityLabel("Shot \(number)\(note.isEmpty ? "" : ", \(note)")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
