//
//  PhotoLibraryView.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Every photo in the project, newest first: those in the storyboard (labeled with their shot)
/// and those that aren't. Pick one to see it large, use it for a shot, save, share, or delete it.
struct PhotoLibraryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var filter: Filter = .all

    enum Filter: Hashable {
        case all, inStoryboard, unused
    }

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 14)]

    var body: some View {
        let all = Array(appModel.photos.photos.reversed())
        let shown = all.filter { photo in
            switch filter {
            case .all: true
            case .inStoryboard: photo.keyframeID != nil
            case .unused: photo.keyframeID == nil
            }
        }

        if all.isEmpty {
            EmptyState(symbol: "photo.on.rectangle.angled",
                       title: "No photos yet",
                       message: "Frame a shot in the viewfinder and press the shutter under the control panel. Every photo you take is kept here.") {
                EmptyView()
            }
        } else {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Show", selection: $filter) {
                        Text("All  \(all.count)").tag(Filter.all)
                        Text("In Storyboard").tag(Filter.inStoryboard)
                        Text("Not Used").tag(Filter.unused)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()

                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(shown) { photo in
                                tile(photo)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if shown.isEmpty {
                        Text(filter == .unused ? "Every photo is in the storyboard." : "No photos are in the storyboard yet.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                if let photo = appModel.selectedLibraryPhoto {
                    PhotoDetail(photo: photo)
                        .frame(width: 380)
                }
            }
        }
    }

    private func tile(_ photo: CapturedPhoto) -> some View {
        let isSelected = photo.id == appModel.selectedLibraryPhoto?.id
        return VStack(alignment: .leading, spacing: 5) {
            PhotoThumbnail(photo: photo, isSelected: isSelected, isPrimary: appModel.photos.isPrimary(photo),
                           width: 180) {
                appModel.selectedLibraryPhotoID = photo.id
            }
            Text(PhotoLibraryView.caption(for: photo, in: appModel))
                .font(.caption)
                .foregroundStyle(photo.keyframeID == nil ? .tertiary : .secondary)
                .lineLimit(1)
        }
    }

    /// "Shot 1A", "Shot 1A · Alternate", or "Not in storyboard".
    static func caption(for photo: CapturedPhoto, in appModel: AppModel) -> String {
        guard let id = photo.keyframeID else { return "Not in storyboard" }
        let shot = "Shot \(appModel.shotCode(id))"
        return appModel.photos.isPrimary(photo) ? shot : shot + " · Alternate"
    }
}

/// The chosen photo large, with what it is and what can be done with it.
private struct PhotoDetail: View {
    @Environment(AppModel.self) private var appModel
    let photo: CapturedPhoto

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotoFrame(image: appModel.photos.image(for: photo)) { ProgressView() }

            VStack(alignment: .leading, spacing: 3) {
                Text(PhotoLibraryView.caption(for: photo, in: appModel))
                    .font(.headline)
                Text([photo.cameraDetails, photo.lighting.name,
                      photo.takenAt.formatted(date: .abbreviated, time: .shortened)].joined(separator: "  ·  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let shots = appModel.animator.timeline.keyframes
            Menu {
                ForEach(shots) { keyframe in
                    Button("Shot \(appModel.shotCode(keyframe.id))", systemImage:
                            appModel.photos.primaryPhoto(for: keyframe.id) == nil ? "rectangle" : "photo") {
                        appModel.usePhoto(photo, forShot: keyframe.id)
                    }
                }
            } label: {
                Label("Use for Shot…", systemImage: "rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(shots.isEmpty)
            .help("Make this the picture for a shot in the storyboard")

            HStack(spacing: 10) {
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    Task { await appModel.saveSelectedPhotoToPhotos() }
                }
                .disabled(appModel.isSavingCapture)
                if let image = appModel.photos.image(for: photo) {
                    let shareable = Image(uiImage: image)
                    ShareLink(item: shareable, preview: SharePreview("Storyboard frame", image: shareable)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                Spacer(minLength: 0)
                Button("Delete", systemImage: "trash", role: .destructive) {
                    appModel.deletePhoto(photo)
                }
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)

            CaptureStatusLine()
        }
        .padding(16)
        .platter()
    }
}
