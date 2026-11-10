//
//  AnimatePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Keyframes and their photos together: the selected keyframe's photo up top, a camera
/// to shoot it, the timeline, and a storyboard of every keyframe's primary photo.
struct AnimatePanel: View {
    @Environment(AppModel.self) private var appModel

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if animator.timeline.keyframes.isEmpty {
                        Text("Add a keyframe to start, even with nothing on the base. Changes you make save to the selected keyframe automatically, so add a new keyframe whenever you want a new pose. Playback moves everything smoothly between keyframes, and each keyframe can hold photos for your storyboard.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        SelectedKeyframeShot()
                        transport
                        ShotList()
                    }
                }
            }
            .scrollIndicators(.hidden)

            editActions
            SlideshowExportStatus()
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
                onScrub: appModel.scrubTimeline(to:)
            )
        }
    }

    private var editActions: some View {
        HStack(spacing: 12) {
            Button {
                appModel.addKeyframe()
            } label: {
                Label("Add Keyframe", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help("Copy the current scene into a new keyframe and select it")

            ExportButton()

            if animator.selectedKeyframe != nil {
                Button("Delete Keyframe", systemImage: "trash", role: .destructive) {
                    appModel.deleteSelectedKeyframe()
                }
                .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
    }
}

/// The selected keyframe: its photo, its other photos, and a camera to take more.
private struct SelectedKeyframeShot: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let keyframe = appModel.animator.selectedKeyframe,
           let number = appModel.animator.number(of: keyframe.id) {
            let keyframePhotos = appModel.photos.photos(for: keyframe.id)
            let focused = appModel.focusedKeyframePhoto

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Keyframe \(number)")
                        .font(.headline)
                    Spacer()
                    if focused?.camera != nil {
                        Button {
                            Task { await appModel.retakeFocusedPhoto() }
                        } label: {
                            Label("Retake", systemImage: "arrow.triangle.2.circlepath.camera")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appModel.canRetakeFocusedPhoto)
                        .help("Shoot this photo again from the same spot with the current lens and lighting")
                    }
                    if let focused {
                        if appModel.photos.isPrimary(focused) {
                            Label("Primary", systemImage: "star.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Make Primary", systemImage: "star") {
                                appModel.setPrimaryPhoto(focused)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                PhotoFrame(image: focused.flatMap { appModel.photos.image(for: $0) }) {
                    if appModel.isCapturing {
                        ProgressView()
                    } else {
                        Text("No photo yet. Frame the shot in your view, then take a photo.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }

                if keyframePhotos.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(keyframePhotos) { photo in
                                PhotoThumbnail(photo: photo,
                                               isSelected: photo.id == focused?.id,
                                               isPrimary: appModel.photos.isPrimary(photo),
                                               width: 80) {
                                    appModel.focusedKeyframePhotoID = photo.id
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                TextField("Shot notes", text: Binding(
                    get: { keyframe.note },
                    set: { appModel.setNote($0, forKeyframe: keyframe.id) }
                ), axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

                CaptureControls(shutterTitle: "Take Photo") {
                    appModel.takePhotoForSelectedKeyframe()
                }
                CaptureStatusLine()

                if appModel.isUpdatingPhotos {
                    Label("Updating photos…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let notice = appModel.keyframeNotice {
                    Label(notice, systemImage: "photo.on.rectangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Label("Changes to the scene save to keyframe \(number) automatically.", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                @Bindable var appModel = appModel
                Toggle("Update photos when a keyframe changes", isOn: $appModel.keepPhotosInSync)
                    .font(.footnote)
                    .help("Re-render a keyframe's photos from their saved angles when you change it. Off: they move to the library.")
            }
        } else {
            Text("No keyframe is selected, so changes aren't being saved to one. Select a keyframe below, or add a new one.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Exports the storyboard as a slideshow video or a printable PDF sheet.
private struct ExportButton: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        Menu {
            Section("Slideshow Video") {
                Picker("Seconds per Shot", selection: $appModel.slideshowSecondsPerShot) {
                    ForEach([1.0, 1.5, 2, 3, 4, 5], id: \.self) { seconds in
                        Text(seconds.formatted(.number.precision(.fractionLength(0...1))) + " s").tag(seconds)
                    }
                }
                Toggle("Crossfade", isOn: $appModel.slideshowCrossfade)
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
        .help("Export a slideshow video or a printable storyboard sheet")
    }
}

/// After exporting: a way to share the file. Before: what each export contains.
private struct SlideshowExportStatus: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let coverage = appModel.slideshowCoverage

        VStack(alignment: .leading, spacing: 8) {
            if let file = appModel.exportedFile {
                ShareLink(item: file.url) {
                    Label(file.shareTitle, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            if let error = appModel.exportError {
                Text(error).font(.footnote).foregroundStyle(.red)
            } else if coverage.total > 0 {
                Text(coverage.withPhoto == coverage.total
                     ? "Export a slideshow of each keyframe's primary photo, or a printable sheet with your notes."
                     : "Export a slideshow of each keyframe's primary photo, or a printable sheet with your notes. \(coverage.withPhoto) of \(coverage.total) keyframes have a photo; the slideshow skips the rest.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
