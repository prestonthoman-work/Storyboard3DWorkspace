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
            Tab("\(WorkspaceTab.base.number). \(WorkspaceTab.base.title)", systemImage: WorkspaceTab.base.symbol, value: WorkspaceTab.base) {
                PanelPage { SetPanel() }
            }
            Tab("\(WorkspaceTab.objects.number). \(WorkspaceTab.objects.title)", systemImage: WorkspaceTab.objects.symbol, value: WorkspaceTab.objects) {
                PanelPage { ObjectsPanel() }
            }
            Tab("\(WorkspaceTab.animate.number). \(WorkspaceTab.animate.title)", systemImage: WorkspaceTab.animate.symbol, value: WorkspaceTab.animate) {
                PanelPage { AnimatePanel() }
            }
            Tab("\(WorkspaceTab.photos.number). \(WorkspaceTab.photos.title)", systemImage: WorkspaceTab.photos.symbol, value: WorkspaceTab.photos) {
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
        // A project can reopen straight on the Animate tab.
        .onAppear {
            if appModel.selectedTab == .animate && !appModel.isTimelineWindowOpen {
                openWindow(id: TimelineWindow.windowID)
            }
        }
        .onDisappear {
            dismissWindow(id: TimelineWindow.windowID)
        }
    }
}

/// Always within reach under the panel: undo and redo, the shutter (from any tab), and two
/// small menus for room guides and snapping.
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
                Menu {
                    Toggle("Labels", systemImage: "tag", isOn: $appModel.showsObjectLabels)
                    Toggle("Eyelines", systemImage: "eye", isOn: $appModel.showsEyelines)
                    Toggle("Onion Skin", systemImage: "square.on.square.dashed", isOn: $appModel.showsOnionSkin)
                } label: {
                    Label("Show", systemImage: "eye")
                }
                .help("Guides in the room: name labels, eyelines and the 180° line, and the previous shot's ghost. None appear in photos.")
                Menu {
                    Toggle("Snap Position", systemImage: "squareshape.split.3x3", isOn: $appModel.isSnappingOn)
                    Toggle("Snap Rotation", systemImage: "angle", isOn: $appModel.isRotationSnappingOn)
                } label: {
                    Label("Snapping", systemImage: appModel.isSnappingOn || appModel.isRotationSnappingOn
                          ? "squareshape.split.3x3" : "square.dashed")
                }
                .help("Position: line objects up when you let go near a guide. Rotation: the rings click onto 15° steps. Hold Option on a keyboard to skip for a moment.")
            }
            .menuStyle(.button)
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

/// Shared page chrome: the way back to projects, the project's name, the workflow steps,
/// and the guide.
private struct PanelPage<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: UI.sectionSpacing) {
                WorkflowStepper()
                SaveErrorBanner()
                if let notice = appModel.projectNotice {
                    HStack(spacing: 12) {
                        StatusMessage(notice, kind: .warning)
                        Button("Dismiss", systemImage: "xmark") { appModel.dismissProjectNotice() }
                            .labelStyle(.iconOnly)
                            .buttonBorderShape(.circle)
                            .controlSize(.small)
                            .help("Dismiss")
                    }
                }
                if !appModel.isGuideHidden {
                    NextStepCard()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
            .animation(.snappy, value: appModel.saveError)
            .navigationTitle(appModel.projectName)
            .toolbar {
                // Leading, where a back button goes: saves and returns to the projects screen.
                ToolbarItem(placement: .topBarLeading) {
                    ToggleImmersiveSpaceButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if appModel.isGuideHidden {
                        Button("Show Guide", systemImage: "signpost.right") {
                            withAnimation(.snappy) { appModel.isGuideHidden = false }
                        }
                        .help("Show the step-by-step guide")
                    }
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
