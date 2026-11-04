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
                        Text("Arrange the objects, then add a keyframe. Rearrange them and add another, and playback moves everything smoothly between keyframes. Each keyframe can hold photos for your storyboard.")
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
            SlideshowExport()
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

            if animator.selectedKeyframe != nil {
                Button("Update", systemImage: "arrow.triangle.2.circlepath") {
                    appModel.updateSelectedKeyframe()
                }
                .help("Save the current arrangement into this keyframe. Its photos are removed if the pose changes.")

                Button("Delete", systemImage: "trash", role: .destructive) {
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

                CaptureControls(shutterTitle: "Take Photo") {
                    appModel.takePhotoForSelectedKeyframe()
                }
                CaptureStatusLine()
            }
        } else {
            Text("Select a keyframe below to see and take its photos.")
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

/// Exports the primary photo of each keyframe as a video slideshow.
private struct SlideshowExport: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let coverage = appModel.slideshowCoverage

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    Task { await appModel.exportSlideshow() }
                } label: {
                    if appModel.isExportingSlideshow {
                        ProgressView()
                    } else {
                        Label("Export Slideshow", systemImage: "film.stack")
                    }
                }
                .disabled(coverage.withPhoto == 0 || appModel.isExportingSlideshow)

                if let url = appModel.slideshowURL {
                    ShareLink(item: url) {
                        Label("Share Slideshow", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .buttonStyle(.bordered)

            if let error = appModel.slideshowError {
                Text(error).font(.footnote).foregroundStyle(.red)
            } else if coverage.total > 0 {
                Text(coverage.withPhoto == coverage.total
                     ? "Uses the primary photo of each keyframe."
                     : "\(coverage.withPhoto) of \(coverage.total) keyframes have a photo. Keyframes without one are skipped.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
