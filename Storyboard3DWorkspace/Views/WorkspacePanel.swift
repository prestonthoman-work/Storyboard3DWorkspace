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
            Tab("Model", systemImage: "cube", value: WorkspaceTab.model) {
                PanelPage(title: "Model") { ModelPanel() }
            }
            Tab("Background", systemImage: "photo", value: WorkspaceTab.background) {
                PanelPage(title: "Background") { BackgroundPanel() }
            }
            Tab("Animate", systemImage: "film", value: WorkspaceTab.animate) {
                PanelPage(title: "Animate") { RequiresModel { AnimatePanel() } }
            }
            Tab("Capture", systemImage: "camera", value: WorkspaceTab.capture) {
                PanelPage(title: "Capture") { RequiresModel { CapturePanel() } }
            }
        }
    }
}

/// Shows a short prompt to create a model first when there isn't one yet.
private struct RequiresModel<Content: View>: View {
    @Environment(AppModel.self) private var appModel
    @ViewBuilder var content: Content

    var body: some View {
        if appModel.hasModel {
            content
        } else {
            ContentUnavailableView {
                Label("No Model Yet", systemImage: "cube")
            } description: {
                Text("Generate a model to animate and capture it.")
            } actions: {
                Button("Go to Model") { appModel.selectedTab = .model }
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
        .frame(width: 460, height: 500)
}
