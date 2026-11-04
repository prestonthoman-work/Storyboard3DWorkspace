//
//  WorkspacePanel.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// The control panel shown while the immersive workspace is open. One tab per workflow step.
struct WorkspacePanel: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedTab) {
            Tab("Base", systemImage: "square.3.layers.3d.down.right", value: WorkspaceTab.base) {
                PanelPage(title: "Base") { BasePanel() }
            }
            Tab("Objects", systemImage: "cube", value: WorkspaceTab.objects) {
                PanelPage(title: "Objects") { ObjectsPanel() }
            }
            Tab("Background", systemImage: "photo", value: WorkspaceTab.background) {
                PanelPage(title: "Background") { BackgroundPanel() }
            }
            Tab("Animate", systemImage: "film", value: WorkspaceTab.animate) {
                PanelPage(title: "Animate") { RequiresObjects { AnimatePanel() } }
            }
            Tab("Capture", systemImage: "camera", value: WorkspaceTab.capture) {
                PanelPage(title: "Capture") { CapturePanel() }
            }
        }
    }
}

/// Shows a short prompt to add objects first when there aren't any yet.
private struct RequiresObjects<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    @ViewBuilder var content: Content

    var body: some View {
        if appModel.hasObjects {
            content
        } else {
            ContentUnavailableView {
                Label("No Objects Yet", systemImage: "cube")
            } description: {
                Text("Add objects to the base to animate them.")
            } actions: {
                Button("Go to Objects") { appModel.selectedTab = .objects }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Shared page chrome: a title and the Exit button.
private struct PanelPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ToggleImmersiveSpaceButton()
                    }
                }
        }
    }
}

#Preview(windowStyle: .automatic) {
    WorkspacePanel()
        .environment(AppModel())
        .frame(width: 480, height: 560)
}
