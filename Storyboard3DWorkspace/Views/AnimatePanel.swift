//
//  AnimatePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// The selected shot: its photo, notes, shot type, and camera. The storyboard window (which
/// opens with this tab) shows every shot; this panel edits one.
struct AnimatePanel: View {
    @Environment(AppModel.self) private var appModel

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        VStack(alignment: .leading, spacing: UI.sectionSpacing) {
            if animator.timeline.keyframes.isEmpty {
                EmptyState(symbol: "rectangle.split.2x2",
                           title: "No shots yet",
                           message: "Arrange the set, then add a shot to save it as panel 1A. Move things and add another, and playback glides between them.") {
                    AddKeyframeButton(title: "Add First Shot")
                        .controlSize(.large)
                }
            } else {
                PanelScroll {
                    if !appModel.isTimelineWindowOpen {
                        StoryboardWindowButton()
                    }
                    SelectedKeyframeShot()
                }

                ActionBar {
                    if !appModel.isTimelineWindowOpen { AddKeyframeButton() }
                    Spacer(minLength: 0)
                    ExportButton()
                }
                SlideshowExportStatus()
            }
        }
    }
}

/// Brings the storyboard window back after it's been closed.
struct StoryboardWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: TimelineWindow.windowID)
        } label: {
            Label("Open Storyboard", systemImage: "rectangle.split.2x2")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .help("See every shot, scene by scene, with playback and the photo library")
    }
}

/// The selected keyframe: its photo, its other photos, notes, and a camera to take more.
private struct SelectedKeyframeShot: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let keyframe = appModel.animator.selectedKeyframe,
           appModel.animator.number(of: keyframe.id) != nil {
            let keyframePhotos = appModel.photos.photos(for: keyframe.id)
            let focused = appModel.focusedKeyframePhoto

            PanelSection("Shot \(appModel.shotCode(keyframe.id))", symbol: "rectangle.on.rectangle") {
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
                            Text("Frame the shot in your view, then press the shutter below the panel.")
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

                if appModel.animator.timeline.keyframes.last?.id != keyframe.id {
                    Picker("Into the next shot", selection: Binding(
                        get: { keyframe.holds },
                        set: { appModel.setHolds($0, forKeyframe: keyframe.id) })) {
                        Label("Ease", systemImage: "point.topleft.down.to.point.bottomright.curvepath").tag(false)
                        Label("Hold, then Cut", systemImage: "square.split.2x1").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .help("Ease moves everything smoothly to the next shot. Hold keeps this pose until the next shot, for storyboards made of distinct poses.")
                }

                CaptureControls()
                CaptureStatusLine()

                if let notice = appModel.keyframeNotice, !appModel.isUpdatingPhotos {
                    StatusMessage(notice, symbol: "photo.on.rectangle")
                }

                @Bindable var appModel = appModel
                Toggle("Re-shoot photos when this shot changes", isOn: $appModel.keepPhotosInSync)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .help("Re-render a keyframe's photos from their saved angles when you change it. Off: they move to the library.")
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "hand.tap")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Choose a shot in the storyboard to edit it and take its photo.")
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
        @Bindable var exports = appModel.exports

        Menu {
            Section {
                Button("Export Animatic", systemImage: "video.badge.waveform") {
                    appModel.exportAnimatic()
                }
                .disabled(!appModel.canExportAnimatic)
                if appModel.captureLook.depthOfField != nil {
                    Toggle("Depth of Field (slower)", isOn: $exports.animaticDepthOfField)
                }
            } header: {
                Text("Animatic Video")
            } footer: {
                Text("The animation as film: objects move while the camera glides between your keyframe photos' angles.")
            }
            Section("Slideshow Video") {
                Picker("Seconds per Shot", selection: $exports.slideshowSecondsPerShot) {
                    ForEach([1.0, 1.5, 2, 3, 4, 5], id: \.self) { seconds in
                        Text(seconds.formatted(.number.precision(.fractionLength(0...1))) + " s").tag(seconds)
                    }
                }
                Toggle("Crossfade", isOn: $exports.slideshowCrossfade)
                Toggle("Shot Captions", isOn: $exports.slideshowCaptions)
                Button("Export Slideshow", systemImage: "film") {
                    Task { await appModel.exportSlideshow() }
                }
                .disabled(appModel.slideshowCoverage.withPhoto == 0)
            }
            Section("Storyboard Sheet (PDF)") {
                Picker("Shots per Page", selection: $exports.sheetLayout) {
                    ForEach(StoryboardSheetExporter.Layout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }
                Toggle("Include Notes", isOn: $exports.sheetIncludesNotes)
                Button("Export Storyboard Sheet", systemImage: "doc.richtext") {
                    appModel.exportStoryboardSheet()
                }
            }
            Section {
                Toggle("Crop to Frame Shape", isOn: $exports.cropsToFrameShape)
            } footer: {
                Text("Videos and the sheet take the camera's frame shape (\(appModel.captureLook.format.label)), such as a real vertical video, instead of 16:9 with bars.")
            }
            Section {
                Button("Export Shot List", systemImage: "tablecells") {
                    appModel.exportShotList()
                }
            } header: {
                Text("Shot List (CSV)")
            } footer: {
                Text("One row per shot with its type, notes, lens, aperture, frame, lighting, and who's in it. Opens in Numbers or Excel.")
            }
        } label: {
            if exports.isExporting {
                ProgressView()
            } else {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(appModel.animator.timeline.keyframes.isEmpty || exports.isExporting)
        .help("Export an animatic, a slideshow video, a printable storyboard sheet, or a shot list")
    }
}

/// After exporting: a way to share the file, or what went wrong.
private struct SlideshowExportStatus: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let coverage = appModel.slideshowCoverage
        let exports = appModel.exports

        if let progress = exports.animaticProgress {
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
        } else if let error = exports.exportError {
            StatusMessage(error, kind: .error)
        } else if let file = exports.exportedFile {
            ShareLink(item: file.url) {
                Label(file.shareTitle, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        } else if coverage.total > 0, coverage.withPhoto < coverage.total {
            Text("\(coverage.withPhoto) of \(coverage.total) shots have a photo. Exports skip the rest.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}
