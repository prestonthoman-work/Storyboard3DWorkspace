//
//  BackdropVisibilityControl.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Whether the backdrop image stays up while you edit, or only comes up for photos. Sits with
/// the camera controls (and with the backdrop picker on the Base tab), so it's always in
/// reach, including while the image itself is hidden.
struct BackdropVisibilityControl: View {
    @Environment(AppModel.self) private var appModel
    /// Leave out the title, when the surrounding section already names the backdrop.
    var showsTitle = true

    var body: some View {
        @Bindable var appModel = appModel

        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Label("Backdrop Image", systemImage: "photo")
                    .font(.callout.weight(.semibold))
            }

            Picker("Backdrop Image", selection: $appModel.backdropVisibilityPreference) {
                ForEach(BackdropVisibility.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .help("Keep the backdrop up while you edit, or keep it out of the way until you take a photo")

            if appModel.backdropVisibilityPreference == .hideBetweenPhotos {
                HStack(spacing: 10) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.opacity)
                    if appModel.isBackdropShownForPhoto {
                        Button("Hide Now", systemImage: "eye.slash") { appModel.hideBackdropForNow() }
                            .disabled(appModel.isCapturing || appModel.captureCountdown != nil)
                            .help("Put the backdrop away until the next photo")
                    } else {
                        Button("Show to Frame", systemImage: "eye") { appModel.showBackdropForFraming() }
                            .help("Bring the backdrop up to line up a shot. It hides again after the photo.")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: appModel.backdropVisibilityPreference)
        .animation(.snappy, value: appModel.isBackdropShownForPhoto)
    }

    private var statusText: String {
        if appModel.isBackdropShownForPhoto {
            return "Showing for this photo. It hides again once the photo is taken."
        }
        return "Hidden while you edit. It comes up when you take a photo."
    }
}
