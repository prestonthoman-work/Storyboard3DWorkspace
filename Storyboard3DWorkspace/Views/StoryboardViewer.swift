//
//  StoryboardViewer.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// A cinema-style screening of the storyboard in its own large window: each shot's
/// primary photo with a slow push-in, crossfades between shots, and the shot number and
/// notes as a caption. Controls fade away while it plays.
struct StoryboardViewer: View {
    static let windowID = "storyboard-viewer"

    @Environment(AppModel.self) private var appModel
    @State private var index = 0
    @State private var isPlaying = true
    @State private var showsControls = true
    /// Drives the push-in: 0 at the start of a shot, 1 at its end.
    @State private var zoom: CGFloat = 0
    @State private var hideControlsTask: Task<Void, Never>?

    private struct Shot: Identifiable {
        let id: Keyframe.ID
        let number: Int
        let image: UIImage
        let note: String
    }

    private var shots: [Shot] {
        appModel.animator.timeline.keyframes.enumerated().compactMap { offset, keyframe in
            guard let photo = appModel.photos.primaryPhoto(for: keyframe.id),
                  let image = appModel.photos.image(for: photo) else { return nil }
            return Shot(id: keyframe.id, number: offset + 1, image: image, note: keyframe.note)
        }
    }

    /// Longer than the slideshow export default, so there's time to read the notes.
    private var secondsPerShot: Double { max(appModel.slideshowSecondsPerShot, 2) + 1.5 }

    var body: some View {
        let shots = shots

        ZStack {
            Color.black

            if shots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.system(size: 44, weight: .light))
                    Text("Take a photo for a shot to screen your storyboard.")
                        .foregroundStyle(.secondary)
                }
            } else {
                let shot = shots[min(index, shots.count - 1)]

                Image(uiImage: shot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(1 + zoom * 0.06)
                    .id(shot.id)
                    .transition(.opacity)

                caption(for: shot, total: shots.count)
                    .id("caption-\(shot.id)")
                    .transition(.opacity.combined(with: .offset(y: 8)))

                controls(count: shots.count)
                    .opacity(showsControls ? 1 : 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .contentShape(Rectangle())
        .onTapGesture { revealControls() }
        .onAppear {
            startShot()
            revealControls()
        }
        .task(id: "\(index)-\(isPlaying)-\(shots.count)") {
            guard isPlaying, shots.count > 1 else { return }
            try? await Task.sleep(for: .seconds(secondsPerShot))
            guard !Task.isCancelled else { return }
            advance(by: 1, count: shots.count)
        }
    }

    private func caption(for shot: Shot, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SHOT \(String(format: "%02d", shot.number))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .tracking(3)
                .foregroundStyle(.white.opacity(0.7))
            if !shot.note.isEmpty {
                Text(shot.note)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }
        }
        .shadow(color: .black.opacity(0.8), radius: 8)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 48)
        .padding(.bottom, 92)
    }

    private func controls(count: Int) -> some View {
        VStack {
            // Story-style progress: one segment per shot.
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { segment in
                    GeometryReader { geometry in
                        Capsule().fill(.white.opacity(0.25))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.white)
                                    .frame(width: geometry.size.width * fill(for: segment))
                            }
                    }
                    .frame(height: 4)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)

            Spacer()

            HStack(spacing: 18) {
                Button("Previous", systemImage: "backward.fill") { advance(by: -1, count: count) }
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying.toggle()
                    if isPlaying { startShot() }
                    revealControls()
                }
                .font(.title2)
                Button("Next", systemImage: "forward.fill") { advance(by: 1, count: count) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .padding(10)
            .glassBackgroundEffect(in: Capsule())
            .padding(.bottom, 24)
        }
        .animation(.easeInOut(duration: 0.4), value: showsControls)
    }

    private func fill(for segment: Int) -> CGFloat {
        if segment < index { return 1 }
        if segment > index { return 0 }
        return isPlaying ? zoom : 1
    }

    private func advance(by step: Int, count: Int) {
        guard count > 0 else { return }
        withAnimation(.easeInOut(duration: 0.9)) {
            index = (index + step + count) % count
        }
        startShot()
    }

    /// Restarts the push-in for the current shot.
    private func startShot() {
        zoom = 0
        guard isPlaying else { return }
        withAnimation(.linear(duration: secondsPerShot)) { zoom = 1 }
    }

    private func revealControls() {
        showsControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, isPlaying else { return }
            showsControls = false
        }
    }
}
