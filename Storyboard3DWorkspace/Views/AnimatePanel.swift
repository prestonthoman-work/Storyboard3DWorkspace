//
//  AnimatePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Keyframes and their photos together: the timeline up top, the selected keyframe's
/// photo and notes with a camera to shoot it, and the storyboard of every keyframe.
struct AnimatePanel: View {
    @Environment(AppModel.self) private var appModel

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        VStack(alignment: .leading, spacing: UI.sectionSpacing) {
            if animator.timeline.keyframes.isEmpty {
                EmptyState(symbol: "diamond",
                           title: "No keyframes yet",
                           message: "Arrange the scene, then add a keyframe to save it as your first shot. Move things and add another, and playback glides between them.") {
                    HStack(spacing: 12) {
                        AddKeyframeButton(title: "Add First Keyframe")
                            .controlSize(.large)
                        TimelineWindowButton()
                    }
                }
            } else {
                // With the Timeline window open, the panel focuses on the selected keyframe
                // instead of repeating the track and storyboard shown there.
                PanelScroll {
                    if appModel.isTimelineWindowOpen {
                        KeyframeStatusLine()
                            .padding(.horizontal, 4)
                    } else {
                        TimelineSection()
                    }
                    SelectedKeyframeShot()
                    if !appModel.isTimelineWindowOpen {
                        ShotList()
                    }
                }
                .animation(.smooth, value: appModel.isTimelineWindowOpen)

                ActionBar {
                    AddKeyframeButton()
                    Spacer(minLength: 0)
                    ExportButton()
                }
                SlideshowExportStatus()
            }
        }
    }
}

/// Opens the large timeline window, or shows that it's already open.
struct TimelineWindowButton: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: TimelineWindow.windowID)
        } label: {
            Label(appModel.isTimelineWindowOpen ? "Timeline Open" : "Open Timeline",
                  systemImage: "rectangle.expand.vertical")
        }
        .buttonStyle(.bordered)
        .disabled(appModel.isTimelineWindowOpen)
        .help("Open the large timeline window")
    }
}

/// Transport, a compact track, and what an edit will do right now.
private struct TimelineSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                KeyframeTransport()
                Spacer(minLength: 8)
                TimelineWindowButton()
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
            }
            TimelineTrack()
            KeyframeStatusLine()
        }
        .padding(UI.sectionPadding)
        .platter()
    }
}

/// The selected keyframe: its photo, its other photos, notes, and a camera to take more.
private struct SelectedKeyframeShot: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let keyframe = appModel.animator.selectedKeyframe,
           let number = appModel.animator.number(of: keyframe.id) {
            let keyframePhotos = appModel.photos.photos(for: keyframe.id)
            let focused = appModel.focusedKeyframePhoto

            PanelSection("Keyframe \(number)", symbol: "diamond.fill") {
                Text(keyframe.time.formatted(.number.precision(.fractionLength(1))) + " s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } content: {
                PhotoFrame(image: focused.flatMap { appModel.photos.image(for: $0) }) {
                    if appModel.isCapturing {
                        ProgressView()
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.largeTitle.weight(.light))
                            Text("Frame the shot in your view, then take a photo.")
                                .font(.callout)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.secondary)
                        .padding()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let focused { photoActions(for: focused) }
                }
                .overlay {
                    if appModel.isUpdatingPhotos {
                        ProgressView("Updating photos…")
                            .padding(14)
                            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: UI.smallCorner))
                    }
                }

                if keyframePhotos.count > 1 {
                    HorizontalStrip(spacing: 8) {
                        ForEach(keyframePhotos) { photo in
                            PhotoThumbnail(photo: photo,
                                           isSelected: photo.id == focused?.id,
                                           isPrimary: appModel.photos.isPrimary(photo),
                                           width: 84) {
                                appModel.focusedKeyframePhotoID = photo.id
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    ShotTypeMenu(shotType: keyframe.shotType) {
                        appModel.setShotType($0, forKeyframe: keyframe.id)
                    }
                    ShotNotesField(keyframe: keyframe)
                }

                CaptureControls(shutterTitle: "Take Photo") {
                    appModel.takePhotoForSelectedKeyframe()
                }
                CaptureStatusLine()

                if let notice = appModel.keyframeNotice, !appModel.isUpdatingPhotos {
                    StatusMessage(notice, symbol: "photo.on.rectangle")
                }

                @Bindable var appModel = appModel
                Toggle("Re-shoot photos when this keyframe changes", isOn: $appModel.keepPhotosInSync)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .help("Re-render a keyframe's photos from their saved angles when you change it. Off: they move to the library.")
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "hand.tap")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Tap a diamond or a shot to edit that keyframe and take its photo.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(UI.sectionPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .platter()
        }
    }

    /// Primary and retake controls floating on the photo.
    private func photoActions(for photo: CapturedPhoto) -> some View {
        HStack(spacing: 6) {
            if photo.camera != nil {
                Button("Retake", systemImage: "arrow.triangle.2.circlepath.camera") {
                    Task { await appModel.retakeFocusedPhoto() }
                }
                .disabled(!appModel.canRetakeFocusedPhoto)
                .help("Shoot this photo again from the same spot with the current lens and lighting")
            }
            if appModel.photos.isPrimary(photo) {
                Label("Primary", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
                    .padding(10)
                    .help("This photo represents the keyframe in the storyboard")
            } else {
                Button("Make Primary", systemImage: "star") {
                    appModel.setPrimaryPhoto(photo)
                }
                .help("Use this photo for the keyframe in the storyboard")
            }
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .padding(4)
        .glassBackgroundEffect(in: Capsule())
        .padding(10)
    }
}

/// Shot notes, typed or spoken. While listening, the words appear after what's already
/// written; switching keyframes stops listening.
private struct ShotNotesField: View {
    @Environment(AppModel.self) private var appModel
    let keyframe: Keyframe

    @State private var dictation = VoiceDictation()
    /// The note as it was when dictation started; spoken words are added after it.
    @State private var noteBeforeDictation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                TextField(dictation.isActive ? "Listening…" : "Add shot notes", text: Binding(
                    get: { keyframe.note },
                    set: { appModel.setNote($0, forKeyframe: keyframe.id) }
                ), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)

                Button {
                    toggleDictation()
                } label: {
                    Label(dictation.isActive ? "Stop Dictation" : "Dictate Notes",
                          systemImage: dictation.isActive ? "stop.fill" : "mic.fill")
                        .symbolEffect(.pulse, isActive: dictation.state == .listening)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .tint(dictation.isActive ? .red : nil)
                .help(dictation.isActive ? "Stop dictating" : "Speak your shot notes")
            }

            if case .failed(let message) = dictation.state {
                StatusMessage(message, kind: .warning)
            }
        }
        .onChange(of: keyframe.id) { dictation.stop() }
        .onDisappear { dictation.stop() }
    }

    private func toggleDictation() {
        if dictation.isActive {
            dictation.stop()
            return
        }
        let id = keyframe.id
        noteBeforeDictation = keyframe.note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await dictation.start { spoken in
                let joined = noteBeforeDictation.isEmpty ? spoken : noteBeforeDictation + " " + spoken
                appModel.setNote(joined, forKeyframe: id)
            }
        }
    }
}

/// Picks how a keyframe is framed. Shows the abbreviation once one is chosen.
struct ShotTypeMenu: View {
    let shotType: ShotType?
    let choose: (ShotType?) -> Void

    var body: some View {
        Menu {
            Picker("Shot Type", selection: Binding(get: { shotType }, set: choose)) {
                Text("None").tag(ShotType?.none)
                ForEach(ShotType.allCases) { type in
                    Label("\(type.name)  (\(type.abbreviation))", systemImage: type.symbol).tag(ShotType?.some(type))
                }
            }
        } label: {
            Label(shotType?.abbreviation ?? "Shot", systemImage: shotType?.symbol ?? "camera.metering.center.weighted")
                .monospaced()
        }
        .help("How this shot is framed, printed on the storyboard")
    }
}

/// Exports the storyboard as a slideshow video or a printable PDF sheet.
private struct ExportButton: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Menu {
            Section {
                Button("Export Animatic", systemImage: "video.badge.waveform") {
                    appModel.exportAnimatic()
                }
                .disabled(!appModel.canExportAnimatic)
            } header: {
                Text("Animatic Video")
            } footer: {
                Text("The animation as film: objects move while the camera glides between your keyframe photos' angles.")
            }
            Section("Slideshow Video") {
                Picker("Seconds per Shot", selection: $appModel.slideshowSecondsPerShot) {
                    ForEach([1.0, 1.5, 2, 3, 4, 5], id: \.self) { seconds in
                        Text(seconds.formatted(.number.precision(.fractionLength(0...1))) + " s").tag(seconds)
                    }
                }
                Toggle("Crossfade", isOn: $appModel.slideshowCrossfade)
                Toggle("Shot Captions", isOn: $appModel.slideshowCaptions)
                Button("Export Slideshow", systemImage: "film") {
                    Task { await appModel.exportSlideshow() }
                }
                .disabled(appModel.slideshowCoverage.withPhoto == 0)
            }
            Section("Storyboard Sheet (PDF)") {
                Picker("Shots per Page", selection: $appModel.sheetLayout) {
                    ForEach(StoryboardSheetExporter.Layout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                Toggle("Include Notes", isOn: $appModel.sheetIncludesNotes)
                Button("Export Storyboard Sheet", systemImage: "doc.richtext") {
                    appModel.exportStoryboardSheet()
                }
            }
        } label: {
            if appModel.isExporting {
                ProgressView()
            } else {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(appModel.animator.timeline.keyframes.isEmpty || appModel.isExporting)
        .help("Export an animatic, a slideshow video, or a printable storyboard sheet")
    }
}

/// After exporting: a way to share the file, or what went wrong.
private struct SlideshowExportStatus: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let coverage = appModel.slideshowCoverage

        if let progress = appModel.animaticProgress {
            HStack(spacing: 12) {
                ProgressView(value: progress)
                    .frame(maxWidth: .infinity)
                Text("Rendering animatic · \(Int(progress * 100))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Cancel") { appModel.cancelAnimatic() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else if let error = appModel.exportError {
            StatusMessage(error, kind: .error)
        } else if let file = appModel.exportedFile {
            ShareLink(item: file.url) {
                Label(file.shareTitle, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        } else if coverage.total > 0, coverage.withPhoto < coverage.total {
            Text("\(coverage.withPhoto) of \(coverage.total) keyframes have a photo. Exports skip the rest.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}
