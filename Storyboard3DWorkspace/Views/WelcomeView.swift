//
//  WelcomeView.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Shown before the immersive workspace opens.
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Storyboard 3D")
                .font(.extraLargeTitle2)

            Text("Build a scene on your table, set a backdrop, and frame it from any angle.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            ToggleImmersiveSpaceButton()
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(40)
    }
}

#Preview(windowStyle: .automatic) {
    WelcomeView()
        .environment(AppModel())
}
