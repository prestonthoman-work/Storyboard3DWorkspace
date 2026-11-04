//
//  AnimatePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct AnimatePanel: View {
    @Environment(AppModel.self) private var appModel

    private var animator: KeyframeAnimator { appModel.animator }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if animator.timeline.keyframes.isEmpty {
                        Text("Arrange the objects, then add a keyframe. Rearrange them and add another, and playback moves everything smoothly between keyframes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        KeyframePhotos()
                        transport
                        keyframeChips
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

    private var keyframeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(animator.timeline.keyframes.enumerated()), id: \.element.id) { index, keyframe in
                    let isSelected = keyframe.id == animator.selectedKeyframeID
                    let hasPhoto = appModel.photos.primaryPhoto(for: keyframe.id) != nil
                    Button("\(index + 1)") { appModel.selectKeyframe(keyframe) }
                        .buttonBorderShape(.circle)
                        .tint(isSelected ? .accentColor : nil)
                        .buttonStyle(.bordered)
                        .overlay(alignment: .bottom) {
                            // A dot marks keyframes that already have a photo.
                            if hasPhoto {
                                Circle().fill(.white).frame(width: 5, height: 5).offset(y: 6)
                            }
                        }
                        .accessibilityLabel("Keyframe \(index + 1)\(hasPhoto ? ", has photo" : "")")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
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

/// The selected keyframe's photos: a large view of one, and a strip to switch between them.
private struct KeyframePhotos: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if let keyframe = appModel.animator.selectedKeyframe,
           let number = appModel.animator.number(of: keyframe.id) {
            let keyframePhotos = appModel.photos.photos(for: keyframe.id)
            let focused = appModel.focusedKeyframePhoto

            VStack(alignment: .leading, spacing: 10) {
                PhotoFrame(image: focused.flatMap { appModel.photos.image(for: $0) }) {
                    VStack(spacing: 10) {
                        Text("No photo for keyframe \(number) yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Take Photo", systemImage: "camera") {
                            appModel.takePhotoForSelectedKeyframe()
                        }
                        .disabled(!appModel.canCapture)
                    }
                }

                if !keyframePhotos.isEmpty {
                    HStack(alignment: .center, spacing: 10) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(keyframePhotos) { photo in
                                    PhotoThumbnail(photo: photo,
                                                   isSelected: photo.id == focused?.id,
                                                   isPrimary: appModel.photos.isPrimary(photo),
                                                   width: 88) {
                                        appModel.focusedKeyframePhotoID = photo.id
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)

                        Button("Take Photo", systemImage: "camera") {
                            appModel.takePhotoForSelectedKeyframe()
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!appModel.canCapture)
                        .help("Take another photo of this keyframe")
                    }

                    if let focused {
                        if appModel.photos.isPrimary(focused) {
                            Label("Primary photo for keyframe \(number)", systemImage: "star.fill")
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
            }
        } else {
            Text("Select a keyframe to see its photos.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
