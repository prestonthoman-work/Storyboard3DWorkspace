//
//  CapturePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

struct CapturePanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            preview

            HStack(spacing: 12) {
                Button {
                    Task { await appModel.captureComposition() }
                } label: {
                    Label("Capture", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.isCapturing || appModel.background == nil)

                if let capture = appModel.lastCapture {
                    Button {
                        Task { await appModel.saveCaptureToPhotos() }
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .disabled(appModel.isSavingCapture)

                    let image = Image(uiImage: capture)
                    ShareLink(item: image, preview: SharePreview("Storyboard frame", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .buttonStyle(.bordered)

            status

            Spacer(minLength: 0)

            Text("Captures the base, its objects, and the backdrop from where you're standing, framed on the scene. Your room and these controls aren't included.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)

            if let capture = appModel.lastCapture {
                Image(uiImage: capture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if !appModel.isCapturing {
                Text("Walk to the angle you like, then capture.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            if appModel.isCapturing {
                ProgressView()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var status: some View {
        switch appModel.captureStatus {
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
