//
//  ContentView.swift
//  Storyboard3DWorkspace
//
//  Created by Preston Thoman on 11/4/26.
//

import SwiftUI

struct ContentView: View {

    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if appModel.immersiveSpaceState == .open {
                WorkspacePanel()
            } else {
                ProjectsView()
            }
        }
        .frame(width: 500, height: 680)
        .task {
            await appModel.loadDefaultBackgroundIfNeeded()
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
