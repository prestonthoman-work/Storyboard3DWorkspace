//
//  WelcomeView.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// The first-launch tour: what the app does in four pages, ending with a choice of where
/// to start. Can be replayed from the projects screen.
struct WelcomeView: View {
    let start: (StarterScene) -> Void
    let dismiss: () -> Void

    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let message: String
        let colors: [Color]
    }

    private let pages: [Page] = [
        Page(symbol: "film.stack",
             title: "Welcome to Storyboard 3D",
             message: "Stage a miniature set on a real table, then frame and photograph every shot of your film.",
             colors: [.indigo, .purple]),
        Page(symbol: "square.3.layers.3d.down.right",
             title: "Set the stage",
             message: "The base lands on your table. Spin it by its edge, pick a surface, and choose a backdrop that always turns to face you.",
             colors: [.teal, .green]),
        Page(symbol: "diamond",
             title: "Build and animate",
             message: "Place objects and pinch to arrange them. Each keyframe saves a moment, and playback glides between them.",
             colors: [.orange, .pink]),
        Page(symbol: "camera.viewfinder",
             title: "Shoot your storyboard",
             message: "Look through the viewfinder and take a photo for each keyframe. Screen it, or export a video or a printable sheet.",
             colors: [.blue, .cyan]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: dismiss)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index]).tag(index)
                }
                StarterPicker(title: "Where would you like to start?", action: start)
                    .padding(.horizontal, 4)
                    .tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                if page > 0 {
                    Button("Back") { withAnimation(.snappy) { page -= 1 } }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if page < pages.count {
                    Button(page == pages.count - 1 ? "Get Started" : "Next") {
                        withAnimation(.snappy) { page += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .frame(height: 52)
        }
        .padding(26)
    }

    private func pageView(_ page: Page) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: page.colors.map { $0.opacity(0.75) },
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 168, height: 168)
                    .shadow(color: page.colors[0].opacity(0.5), radius: 30)
                Image(systemName: page.symbol)
                    .font(.system(size: 66, weight: .light))
                    .symbolEffect(.bounce, value: self.page)
            }
            VStack(spacing: 10) {
                Text(page.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The ways to begin a project: blank, or one of the ready-made sets.
struct StarterPicker: View {
    var title: String?
    let action: (StarterScene) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title)
                    .font(.title2.weight(.bold))
                    .padding(.bottom, 4)
            }
            ForEach(StarterScene.allCases) { starter in
                Button {
                    action(starter)
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: UI.smallCorner, style: .continuous)
                                .fill(starter.template.swatch.opacity(starter == .blank ? 0.25 : 0.85))
                            Image(systemName: starter.symbol)
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                        .frame(width: 64, height: 64)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(starter.name)
                                    .font(.headline)
                                if starter.isAnimated {
                                    Badge(text: "Animated", symbol: "play.fill")
                                }
                            }
                            Text(starter.subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .platter()
                    .contentShape(RoundedRectangle(cornerRadius: UI.corner))
                }
                .buttonStyle(.plain)
                .hoverEffect()
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
}
