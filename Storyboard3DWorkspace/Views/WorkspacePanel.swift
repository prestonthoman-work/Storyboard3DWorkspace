//
//  WorkspacePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// The control panel shown while the immersive workspace is open. One tab per workflow step.
struct WorkspacePanel: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedTab) {
            Tab(WorkspaceTab.set.title, systemImage: WorkspaceTab.set.symbol, value: WorkspaceTab.set) {
                PanelPage { SetPanel() }
            }
            Tab(WorkspaceTab.objects.title, systemImage: WorkspaceTab.objects.symbol, value: WorkspaceTab.objects) {
                PanelPage { ObjectsPanel() }
            }
            Tab(WorkspaceTab.animate.title, systemImage: WorkspaceTab.animate.symbol, value: WorkspaceTab.animate) {
                PanelPage { AnimatePanel() }
            }
            Tab(WorkspaceTab.photos.title, systemImage: WorkspaceTab.photos.symbol, value: WorkspaceTab.photos) {
                PanelPage { CapturePanel() }
            }
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            WorkspaceOrnament()
                .padding(.top, 12)
        }
        // The timeline window comes up with the Animate tab, so keyframes are always in reach.
        .onChange(of: appModel.selectedTab) { _, tab in
            if tab == .animate && !appModel.isTimelineWindowOpen {
                openWindow(id: TimelineWindow.windowID)
            }
        }
        .onDisappear {
            dismissWindow(id: TimelineWindow.windowID)
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
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo")
                Button("Redo", systemImage: "arrow.uturn.forward") { appModel.redo() }
                    .disabled(!appModel.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
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
                Toggle(isOn: $appModel.showsObjectLabels) {
                    Label("Labels", systemImage: "tag")
                }
                .help("Show each object's name above it in the room. Labels never appear in photos.")
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

/// Shared page chrome: the project's name, the way back to projects, and the guide.
private struct PanelPage<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: UI.sectionSpacing) {
                if !appModel.isGuideHidden {
                    NextStepCard()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
            .navigationTitle(appModel.projectName)
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
        .frame(width: UI.panelSize.width, height: UI.panelSize.height)
}
