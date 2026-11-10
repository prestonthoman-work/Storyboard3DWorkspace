//
//  CapturePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Free shooting and the photo library: the chosen photo large, every photo below, and the
/// camera pinned at the bottom.
struct CapturePanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: UI.sectionSpacing) {
            PanelScroll {
                selectedPhoto
                    .animation(.smooth(duration: 0.3), value: appModel.selectedLibraryPhoto?.id)
                PhotoLibraryGrid()
                    .animation(.snappy, value: appModel.photos.photos.map(\.id))
            }

            VStack(alignment: .leading, spacing: 10) {
                CaptureTargetLine()
                CaptureControls {
                    appModel.startCapture()
                }
                CaptureStatusLine()
            }
            .padding(UI.sectionPadding)
            .platter()
        }
    }

    @ViewBuilder
    private var selectedPhoto: some View {
        let photo = appModel.selectedLibraryPhoto

        VStack(alignment: .leading, spacing: 8) {
            PhotoFrame(image: photo.flatMap { appModel.photos.image(for: $0) }) {
                if appModel.isCapturing {
                    ProgressView()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.largeTitle.weight(.light))
                        Text("Line up your shot in the frame in your view, then press the shutter.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let photo { photoActions(for: photo) }
            }

            if let photo {
                Text(PhotoLibraryGrid.label(for: photo, in: appModel) + " · \(photo.lens.label)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Save, share, and delete, floating on the photo.
    private func photoActions(for photo: CapturedPhoto) -> some View {
        HStack(spacing: 6) {
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
                Task { await appModel.saveSelectedPhotoToPhotos() }
            }
            .disabled(appModel.isSavingCapture)
            .help("Save to your Photos library")

            if let image = appModel.photos.image(for: photo) {
                let shareable = Image(uiImage: image)
                ShareLink(item: shareable, preview: SharePreview("Storyboard frame", image: shareable)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            Button("Delete", systemImage: "trash", role: .destructive) {
                appModel.deletePhoto(photo)
            }
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .padding(4)
        .glassBackgroundEffect(in: Capsule())
        .padding(10)
    }
}

/// Before shooting: where the photo will go, and a menu to send it to a keyframe instead.
private struct CaptureTargetLine: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let keyframes = appModel.animator.timeline.keyframes

        HStack(spacing: 10) {
            if let target = appModel.captureTarget {
                StatusMessage("Attaches to keyframe \(target.number)", symbol: "diamond.fill")
            } else {
                StatusMessage("Goes to the library", symbol: "photo.on.rectangle")
            }
            if !keyframes.isEmpty {
                Menu {
                    ForEach(Array(keyframes.enumerated()), id: \.element.id) { index, keyframe in
                        Button {
                            appModel.selectKeyframe(keyframe)
                        } label: {
                            Label("Keyframe \(index + 1)" + (keyframe.shotType.map { "  ·  \($0.abbreviation)" } ?? ""),
                                  systemImage: appModel.photos.primaryPhoto(for: keyframe.id) == nil ? "diamond" : "checkmark.diamond.fill")
                        }
                    }
                } label: {
                    Label("Attach To", systemImage: "diamond")
                }
                .controlSize(.small)
                .fixedSize()
                .help("Pose the scene at a keyframe so the next photo attaches to it")
            }
        }
    }
}

/// Every photo taken this session, newest first, including ones removed from keyframes.
private struct PhotoLibraryGrid: View {
    @Environment(AppModel.self) private var appModel

    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 12)]

    var body: some View {
        let photos = Array(appModel.photos.photos.reversed())
        if !photos.isEmpty {
            PanelSection("Library", symbol: "photo.stack") {
                Text("\(photos.count)").monospacedDigit().foregroundStyle(.secondary)
            } content: {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(photos) { photo in
                        VStack(alignment: .leading, spacing: 4) {
                            PhotoThumbnail(photo: photo,
                                           isSelected: photo.id == appModel.selectedLibraryPhoto?.id,
                                           isPrimary: appModel.photos.isPrimary(photo),
                                           width: 148) {
                                appModel.selectedLibraryPhotoID = photo.id
                            }
                            Text(Self.label(for: photo, in: appModel))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    static func label(for photo: CapturedPhoto, in appModel: AppModel) -> String {
        switch photo.assignment {
        case .keyframe(let id):
            let name = appModel.animator.number(of: id).map { "Keyframe \($0)" } ?? "Keyframe"
            return appModel.photos.isPrimary(photo) ? "\(name) · Primary" : name
        case .unassigned:
            return "No keyframe"
        case .removed:
            return "Removed from keyframe"
        }
    }
}
