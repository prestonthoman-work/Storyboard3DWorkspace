//
//  CapturePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// The camera: the last photo large, where the next one will go, lighting and lens, and the
/// way into the photo library. The shutter is the round button under the control panel.
struct CapturePanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: UI.sectionSpacing) {
            PanelScroll {
                lastPhoto
                    .animation(.smooth(duration: 0.3), value: appModel.selectedLibraryPhoto?.id)

                Button {
                    appModel.storyboardMode = .library
                    openWindow(id: TimelineWindow.windowID)
                } label: {
                    Label("Photo Library  ·  \(appModel.photos.photos.count)", systemImage: "photo.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("See every photo in this project, use one for a shot, save, share, or delete")
            }

            VStack(alignment: .leading, spacing: 10) {
                CaptureTargetLine()
                CaptureControls()
                Label("Press the shutter below the panel to take the photo.", systemImage: "arrow.down.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                CaptureStatusLine()
            }
            .padding(UI.sectionPadding)
            .platter()
        }
    }

    @ViewBuilder
    private var lastPhoto: some View {
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
            if let photo {
                Text(PhotoLibraryView.caption(for: photo, in: appModel) + "  ·  \(photo.cameraDetails)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Before shooting: where the photo will go, and a menu to send it to another shot instead.
private struct CaptureTargetLine: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        let keyframes = appModel.animator.timeline.keyframes

        HStack(spacing: 10) {
            if let target = appModel.captureTarget {
                StatusMessage("Goes to shot \(appModel.shotCode(target.keyframe.id))", symbol: "rectangle.on.rectangle")
            } else {
                StatusMessage("Goes to the library", symbol: "photo.on.rectangle")
            }
            if !keyframes.isEmpty {
                Menu {
                    ForEach(keyframes) { keyframe in
                        Button {
                            appModel.selectKeyframe(keyframe)
                        } label: {
                            Label("Shot \(appModel.shotCode(keyframe.id))" + (keyframe.shotType.map { "  ·  \($0.abbreviation)" } ?? ""),
                                  systemImage: appModel.photos.primaryPhoto(for: keyframe.id) == nil ? "rectangle" : "checkmark.rectangle")
                        }
                    }
                } label: {
                    Label("Choose Shot", systemImage: "rectangle.on.rectangle")
                }
                .controlSize(.small)
                .fixedSize()
                .help("Set the scene to a shot so the next photo attaches to it")
            }
        }
    }
}
