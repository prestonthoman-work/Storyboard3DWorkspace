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
                        StoryboardStrip()
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

                if let notice = appModel.keyframeNotice {
                    Label(notice, systemImage: "photo.on.rectangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Label("Changes to the scene save to keyframe \(number) automatically.", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("No keyframe is selected, so changes aren't being saved to one. Select a keyframe below, or add a new one.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every keyframe as a card showing its primary photo, in timeline order.
private struct StoryboardStrip: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Storyboard")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(appModel.animator.timeline.keyframes.enumerated()), id: \.element.id) { index, keyframe in
                        StoryboardCard(
                            number: index + 1,
                            primary: appModel.photos.primaryPhoto(for: keyframe.id),
                            photoCount: appModel.photos.photos(for: keyframe.id).count,
                            isSelected: keyframe.id == appModel.animator.selectedKeyframeID
                        ) {
                            appModel.selectKeyframe(keyframe)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct StoryboardCard: View {
    let number: Int
    let primary: CapturedPhoto?
    let photoCount: Int
    let isSelected: Bool
    let action: () -> Void

    private let width: CGFloat = 104

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 3)
                }

                HStack {
                    Text("\(number)")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if photoCount > 1 {
                        Label("\(photoCount)", systemImage: "photo.stack")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: width)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityLabel("Keyframe \(number), \(photoCount == 0 ? "no photos" : "\(photoCount) photos")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
