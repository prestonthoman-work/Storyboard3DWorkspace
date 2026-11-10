//
//  WorkspacePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI
import TipKit

/// The control panel shown while the immersive workspace is open. One tab per workflow step.
struct WorkspacePanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedTab) {
            Tab("Base", systemImage: "square.3.layers.3d.down.right", value: WorkspaceTab.base) {
                PanelPage(title: "Base", tip: BaseTip()) { BasePanel() }
            }
            Tab("Objects", systemImage: "cube", value: WorkspaceTab.objects) {
                PanelPage(title: "Objects", tip: ObjectsTip()) { ObjectsPanel() }
            }
            Tab("Background", systemImage: "photo", value: WorkspaceTab.background) {
                PanelPage(title: "Background", tip: BackgroundTip()) { BackgroundPanel() }
            }
            Tab("Animate", systemImage: "film", value: WorkspaceTab.animate) {
                PanelPage(title: "Animate", tip: AnimateTip()) { AnimatePanel() }
            }
            Tab("Capture", systemImage: "camera", value: WorkspaceTab.capture) {
                PanelPage(title: "Capture", tip: CaptureTip()) { CapturePanel() }
            }
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            WorkspaceOrnament()
                .padding(.top, 12)
        }
    }
}

/// Always within reach under the panel: undo and redo, a shutter that works from any
/// tab, and quick toggles for previewing the lighting and snapping.
private struct WorkspaceOrnament: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Button("Undo", systemImage: "arrow.uturn.backward") { appModel.undo() }
                    .disabled(!appModel.canUndo)
                    .help("Undo")
                Button("Redo", systemImage: "arrow.uturn.forward") { appModel.redo() }
                    .disabled(!appModel.canRedo)
                    .help("Redo")
            }

            ShutterButton()

            HStack(spacing: 4) {
                Toggle(isOn: $appModel.isLightingPreviewOn) {
                    Label("Preview Lighting", systemImage: appModel.captureLighting.symbol)
                }
                .help("Light the scene in your space with the \(appModel.captureLighting.name) capture lighting")
                Toggle(isOn: $appModel.isSnappingOn) {
                    Label("Snapping", systemImage: "squareshape.split.3x3")
                }
                .help("Snap rotation to 15° and line objects up with each other")
            }
            .toggleStyle(.button)
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        .padding(10)
        .glassBackgroundEffect(in: Capsule())
    }
}

/// A camera-style shutter: a ring around a solid disc. During the self-timer it shows
/// the count and cancels.
private struct ShutterButton: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button {
            if appModel.captureCountdown != nil {
                appModel.cancelCapture()
            } else {
                appModel.startCapture()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                if let remaining = appModel.captureCountdown {
                    Text("\(remaining)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                } else if appModel.isCapturing {
                    ProgressView()
                } else {
                    Circle()
                        .fill(.white)
                        .padding(7)
                }
            }
            .frame(width: 60, height: 60)
            .contentShape(Circle())
            .animation(.snappy, value: appModel.captureCountdown)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(appModel.captureCountdown == nil && !appModel.canCapture)
        .accessibilityLabel(appModel.captureCountdown == nil ? "Take photo" : "Cancel photo timer")
        .help(appModel.captureCountdown == nil ? "Take a photo from where you're looking" : "Cancel")
    }
}

/// Shared page chrome: a title and the Exit button.
private struct PanelPage<Content: View, PageTip: Tip>: View {
    let title: String
    /// Shown above the page until dismissed.
    let tip: PageTip
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TipView(tip)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ToggleImmersiveSpaceButton()
                }
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    WorkspacePanel()
        .environment(AppModel())
        .frame(width: 500, height: 680)
}
