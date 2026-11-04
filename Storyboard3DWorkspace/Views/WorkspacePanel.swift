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
                PanelPage(title: "Animate") { AnimatePanel() }
            }
            Tab("Capture", systemImage: "camera", value: WorkspaceTab.capture) {
                PanelPage(title: "Capture") { CapturePanel() }
            }
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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        UndoRedoButtons()
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

/// Undo and Redo for edits to the base, objects, keyframes, and photos.
private struct UndoRedoButtons: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button("Undo", systemImage: "arrow.uturn.backward") { appModel.undo() }
            .disabled(!appModel.canUndo)
            .help("Undo")
        Button("Redo", systemImage: "arrow.uturn.forward") { appModel.redo() }
            .disabled(!appModel.canRedo)
            .help("Redo")
    }
}
