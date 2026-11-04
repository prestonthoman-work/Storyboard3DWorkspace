//
//  CapturePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct CapturePanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    selectedPhoto
                    PhotoLibraryGrid()
                }
            }
            .scrollIndicators(.hidden)

            CaptureTargetLine()

            HStack(spacing: 12) {
                if let remaining = appModel.captureCountdown {
                    Button("Cancel (\(remaining))", systemImage: "xmark") {
                        appModel.cancelCapture()
                    }
                } else {
                    Button {
                        appModel.startCapture()
                    } label: {
                        Label("Capture", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appModel.canCapture)
                }

                Picker("Lens", selection: $appModel.captureLens) {
                    ForEach(CaptureLens.allCases) { lens in
                        Text(lens.label).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appModel.captureCountdown != nil)
            }
            .buttonStyle(.bordered)

            status
        }
    }

    @ViewBuilder
    private var selectedPhoto: some View {
        let photo = appModel.selectedLibraryPhoto

        PhotoFrame(image: photo.flatMap { appModel.photos.image(for: $0) }) {
            if appModel.isCapturing {
                ProgressView()
            } else {
                Text("Line up your shot in the frame in your view, then capture.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }

        if let photo {
            HStack(spacing: 10) {
                Text(PhotoLibraryGrid.label(for: photo, in: appModel) + " · \(photo.lens.label)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await appModel.saveSelectedPhotoToPhotos() }
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                }
                .disabled(appModel.isSavingCapture)

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
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch appModel.captureStatus {
        case .attached(let number):
            Label("Added to keyframe \(number).", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .libraryOnly:
            Label("Saved to the library. It isn't attached to a keyframe.", systemImage: "photo.on.rectangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }
}

/// Before shooting: says whether the photo will attach to a keyframe.
private struct CaptureTargetLine: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let target = appModel.captureTarget {
                Label("Photos will attach to keyframe \(target.number).", systemImage: "film")
            } else if appModel.animator.timeline.keyframes.isEmpty {
                Label("Photos go to the library. Add keyframes in Animate to build a storyboard.",
                      systemImage: "photo.on.rectangle")
            } else {
                Label("The scene isn't at a keyframe, so photos go to the library only. Select a keyframe in Animate to attach them.",
                      systemImage: "photo.on.rectangle")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Every photo taken this session, newest first, including ones removed from keyframes.
private struct PhotoLibraryGrid: View {
    @Environment(AppModel.self) private var appModel

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]

    var body: some View {
        let photos = Array(appModel.photos.photos.reversed())
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Library (\(photos.count))")
                    .font(.headline)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(photos) { photo in
                        VStack(alignment: .leading, spacing: 4) {
                            PhotoThumbnail(photo: photo,
                                           isSelected: photo.id == appModel.selectedLibraryPhoto?.id,
                                           isPrimary: appModel.photos.isPrimary(photo),
                                           width: 120) {
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
