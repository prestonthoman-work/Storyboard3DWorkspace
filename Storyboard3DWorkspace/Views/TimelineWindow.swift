//
//  TimelineWindow.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// The storyboard: every shot as a panel, four to a row, grouped by scene and labeled the way
/// storyboard artists do (1A, 1B, 1C, then 2A when a new scene starts). Above it, playback
/// and a slim timeline for timing. The Library shows every photo in the project.
/// Opens with the Animate tab.
struct TimelineWindow: View {
    static let windowID = "timeline"

    @Environment(AppModel.self) private var appModel

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 16) {
            header

            switch appModel.storyboardMode {
            case .library:
                PhotoLibraryView()
            case .storyboard:
                if animator.timeline.keyframes.isEmpty {
                    emptyState
                } else {
                    playback
                    StoryboardSheet()
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appModel.isTimelineWindowOpen = true }
        .onDisappear { appModel.isTimelineWindowOpen = false }
    }

    private var header: some View {
        @Bindable var appModel = appModel

        return HStack(alignment: .center, spacing: 16) {
            Text(appModel.projectName)
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            Picker("View", selection: $appModel.storyboardMode) {
                Text("Storyboard").tag(AppModel.StoryboardMode.storyboard)
                Text("Library  \(appModel.photos.photos.count)").tag(AppModel.StoryboardMode.library)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer(minLength: 12)

            if appModel.storyboardMode == .storyboard {
                PlayStoryboardButton()
                Button("New Scene", systemImage: "rectangle.stack.badge.plus") {
                    withAnimation(.snappy) { appModel.addScene() }
                }
                .buttonStyle(.bordered)
                .disabled(animator.timeline.keyframes.isEmpty)
                .help("Start scene \(animator.timeline.scenes.count + 1) with a new shot of the set as it is now")
                AddKeyframeButton()
                    .keyboardShortcut("k", modifiers: [])
            }
        }
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                KeyframeTransport(showsShortcuts: true)
                Spacer(minLength: 8)
                KeyframeStatusLine()
                    .frame(maxWidth: 420, alignment: .trailing)
            }
            TimelineTrack()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .platter()
    }

    private var emptyState: some View {
        EmptyState(symbol: "rectangle.split.2x2",
                   title: "No shots yet",
                   message: "Arrange the set, then add a shot to save it as panel 1A. Move things and add another, and playback glides between them.") {
            AddKeyframeButton(title: "Add First Shot")
                .controlSize(.large)
        }
    }
}

/// Plays the storyboard full screen, photo by photo.
private struct PlayStoryboardButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Present", systemImage: "play.rectangle") {
            openWindow(id: StoryboardViewer.windowID)
        }
        .buttonStyle(.bordered)
        .disabled(appModel.slideshowCoverage.withPhoto == 0)
        .help("Watch the storyboard full screen, shot by shot. Needs at least one photo.")
    }
}

/// Adds a shot after the selected one, holding the set as it is now.
struct AddKeyframeButton: View {
    @Environment(AppModel.self) private var appModel
    var title: String?

    var body: some View {
        Button {
            withAnimation(.snappy) { appModel.addKeyframe() }
        } label: {
            Label(title ?? "Add Shot", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .help("Save the set as it is now as a new shot after the selected one (K)")
    }
}

// MARK: Storyboard

/// The scenes, each a heading and its shots four to a row.
private struct StoryboardSheet: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let scenes = appModel.animator.timeline.scenes

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(scenes) { scene in
                        SceneSection(scene: scene)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
            // Keep the selected shot in view as playback moves through the shots.
            .onChange(of: appModel.animator.selectedKeyframeID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

private struct SceneSection: View {
    @Environment(AppModel.self) private var appModel
    let scene: StoryboardScene

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18, alignment: .top), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("SCENE \(scene.number)")
                    .font(.headline.weight(.heavy))
                    .tracking(1.6)
                SceneTitleField(scene: scene)
                Spacer(minLength: 8)
                Text(scene.shots.count == 1 ? "1 shot" : "\(scene.shots.count) shots")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                ForEach(Array(scene.shots.enumerated()), id: \.element.id) { offset, keyframe in
                    StoryboardPanel(keyframe: keyframe, label: ShotLabel(scene: scene.number, shot: offset))
                        .id(keyframe.id)
                }
            }
        }
    }
}

/// The scene's title, edited in place, like "Kitchen, Night".
private struct SceneTitleField: View {
    @Environment(AppModel.self) private var appModel
    let scene: StoryboardScene
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Add a scene title", text: $title)
            .font(.headline)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .frame(maxWidth: 360)
            .onAppear { title = scene.title }
            .onChange(of: scene.title) { _, new in if !isFocused { title = new } }
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            .onSubmit(commit)
            .accessibilityLabel("Scene \(scene.number) title")
    }

    private func commit() {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines) != scene.title else { return }
        appModel.setSceneTitle(title, forSceneContaining: scene.id)
    }
}

/// One storyboard panel: its label, the shot's picture, and its action notes underneath.
private struct StoryboardPanel: View {
    @Environment(AppModel.self) private var appModel
    let keyframe: Keyframe
    let label: ShotLabel

    var body: some View {
        let timeline = appModel.animator.timeline
        let index = timeline.index(of: keyframe.id) ?? 0
        let isSelected = keyframe.id == appModel.animator.selectedKeyframeID
        let primary = appModel.photos.primaryPhoto(for: keyframe.id)
        let photoCount = appModel.photos.photos(for: keyframe.id).count

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label.code)
                    .font(.title3.weight(.bold).monospaced())
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                if let shotType = keyframe.shotType {
                    Text(shotType.abbreviation)
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if photoCount > 1 {
                    Label("\(photoCount)", systemImage: "photo.stack")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(keyframe.time.formatted(.number.precision(.fractionLength(1))) + "s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Button {
                appModel.selectKeyframe(keyframe)
            } label: {
                ZStack {
                    Rectangle().fill(.white.opacity(0.05))
                    if let primary {
                        Image(uiImage: primary.thumbnail)
                            .resizable()
                            .aspectRatio(16 / 9, contentMode: .fill)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "camera")
                                .font(.title3.weight(.light))
                            Text("No photo yet")
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.22), lineWidth: isSelected ? 3 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverEffect()

            Text(keyframe.note.isEmpty ? "No notes" : keyframe.note)
                .font(.callout)
                .foregroundStyle(keyframe.note.isEmpty ? .tertiary : .secondary)
                .lineLimit(3, reservesSpace: true)
        }
        .draggable(keyframe.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            withAnimation(.snappy) { appModel.moveKeyframe(id, to: index) }
            return true
        }
        .contextMenu {
            if index > 0 {
                if timeline.startsScene(at: index) {
                    Button("Join Scene \(label.scene - 1)", systemImage: "arrow.uturn.up") {
                        withAnimation(.snappy) { appModel.setStartsScene(false, forKeyframe: keyframe.id) }
                    }
                } else {
                    Button("Start New Scene Here", systemImage: "rectangle.stack.badge.plus") {
                        withAnimation(.snappy) { appModel.setStartsScene(true, forKeyframe: keyframe.id) }
                    }
                }
            }
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
            .disabled(index == timeline.keyframes.count - 1)
            Divider()
            Button("Delete Shot", systemImage: "trash", role: .destructive) {
                withAnimation(.snappy) { appModel.deleteKeyframe(keyframe.id) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shot \(label.code)\(keyframe.shotType.map { ", \($0.name)" } ?? "")\(keyframe.note.isEmpty ? "" : ", \(keyframe.note)")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
