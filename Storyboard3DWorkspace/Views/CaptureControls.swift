//
//  CaptureControls.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Lens choice and the shutter button, shared by the Animate and Capture tabs.
/// While the self-timer runs, the shutter becomes a Cancel button showing the count.
struct CaptureControls: View {
    @Environment(AppModel.self) private var appModel
    var shutterTitle = "Capture"
    let shutter: () -> Void

    var body: some View {
        @Bindable var appModel = appModel

        HStack(spacing: 12) {
            Picker("Lens", selection: $appModel.captureLens) {
                ForEach(CaptureLens.allCases) { lens in
                    Text(lens.label).tag(lens)
                }
            }
            .pickerStyle(.segmented)
            .disabled(appModel.captureCountdown != nil)
            .help("Lens focal length, like a Blender camera")

            if let remaining = appModel.captureCountdown {
                Button("Cancel (\(remaining))", systemImage: "xmark") {
                    appModel.cancelCapture()
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: shutter) {
                    Label(shutterTitle, systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.canCapture)
            }
        }
    }
}

/// The result of the last capture attempt, or an error.
struct CaptureStatusLine: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        switch appModel.captureStatus {
        case .attached(let number):
            Label("Added to keyframe \(number).", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .libraryOnly:
            Label("Saved to the library. It isn't attached to a keyframe.", systemImage: "photo.on.rectangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .sceneChanged(let number):
            Label("Objects have moved since keyframe \(number) was selected. Select it again to restore its pose, or choose Update to save the new one.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
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
