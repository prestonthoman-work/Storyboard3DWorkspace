//
//  ExportController.swift
//  Storyboard3DWorkspace
//

import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// Turns the storyboard into files to share: an animatic video, a slideshow video of the
/// keyframe photos, or a printable PDF sheet. Holds the export settings (remembered across
/// launches) and the progress and result of the latest export.
///
/// `AppModel` owns one and hands it the project content to export, so this type never
/// reaches back into the scene or the undo history.
@MainActor
@Observable
final class ExportController {
    struct ExportedFile {
        let url: URL
        let shareTitle: String
    }

    private(set) var isExporting = false
    /// The latest finished export, until the project changes.
    private(set) var exportedFile: ExportedFile?
    private(set) var exportError: String?
    /// 0...1 while an animatic renders.
    private(set) var animaticProgress: Double?
    @ObservationIgnored private var animaticTask: Task<Void, Never>?

    static let animaticFramesPerSecond: Int32 = 24

    // MARK: Settings, remembered across launches

    var slideshowSecondsPerShot: Double = UserDefaults.standard.object(forKey: "slideshowSecondsPerShot") as? Double ?? 2 {
        didSet { UserDefaults.standard.set(slideshowSecondsPerShot, forKey: "slideshowSecondsPerShot") }
    }
    var slideshowCrossfade: Bool = UserDefaults.standard.object(forKey: "slideshowCrossfade") as? Bool ?? true {
        didSet { UserDefaults.standard.set(slideshowCrossfade, forKey: "slideshowCrossfade") }
    }
    /// Burn "SHOT 03 · WS · notes" into each slide, like a storyboard panel.
    var slideshowCaptions: Bool = UserDefaults.standard.object(forKey: "slideshowCaptions") as? Bool ?? true {
        didSet { UserDefaults.standard.set(slideshowCaptions, forKey: "slideshowCaptions") }
    }
    var sheetLayout: StoryboardSheetExporter.Layout =
        StoryboardSheetExporter.Layout(rawValue: UserDefaults.standard.integer(forKey: "sheetLayout")) ?? .six {
        didSet { UserDefaults.standard.set(sheetLayout.rawValue, forKey: "sheetLayout") }
    }
    var sheetIncludesNotes: Bool = UserDefaults.standard.object(forKey: "sheetIncludesNotes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sheetIncludesNotes, forKey: "sheetIncludesNotes") }
    }

    /// Forgets the latest export, because the project changed since and the file is out of date.
    func invalidate() {
        exportedFile = nil
    }

    // MARK: What can be exported

    /// How many keyframes have a primary photo, out of all keyframes.
    static func coverage(of keyframes: [Keyframe], photos: PhotoLibrary) -> (withPhoto: Int, total: Int) {
        (keyframes.filter { photos.primaryPhoto(for: $0.id) != nil }.count, keyframes.count)
    }

    /// The animatic's camera move: each keyframe's primary photo angle, in timeline order.
    static func cameraPath(for keyframes: [Keyframe], photos: PhotoLibrary) -> CameraPath {
        CameraPath(stops: keyframes.compactMap { keyframe in
            guard let camera = photos.primaryPhoto(for: keyframe.id)?.camera else { return nil }
            return CameraPath.Stop(time: keyframe.time, camera: camera)
        })
    }

    // MARK: Slideshow

    /// Exports an MP4 of each keyframe's primary photo, in timeline order. Keyframes
    /// without a photo are skipped; other photos taken at a keyframe aren't included.
    func exportSlideshow(keyframes: [Keyframe], photos: PhotoLibrary, title: String) async {
        guard !isExporting else { return }
        let captions = slideshowCaptions
        let slides: [CGImage] = keyframes.enumerated().compactMap { index, keyframe in
            guard let photo = photos.primaryPhoto(for: keyframe.id), let image = photos.image(for: photo)?.cgImage
            else { return nil }
            guard captions else { return image }
            return SlideCaption.burn(SlideCaption.caption(number: index + 1, shotType: keyframe.shotType,
                                                          note: keyframe.note), into: image)
        }
        guard !slides.isEmpty else { return }

        isExporting = true
        exportError = nil
        exportedFile = nil
        defer { isExporting = false }

        let url = Self.exportURL(title: title, suffix: "Slideshow", fileExtension: "mp4")
        let seconds = slideshowSecondsPerShot
        let crossfade = slideshowCrossfade
        do {
            try await Task.detached(priority: .userInitiated) {
                try await SlideshowExporter.export(slides, secondsPerSlide: seconds, crossfade: crossfade, to: url)
            }.value
            exportedFile = ExportedFile(url: url, shareTitle: "Share Slideshow")
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: Animatic

    /// Everything an animatic render reads, captured when the export starts.
    struct AnimaticInput {
        let timeline: KeyframeTimeline
        let cameraPath: CameraPath
        /// Where the backdrop sits; nil leaves it where it is.
        let backdropPose: Transform?
        let background: CGImage
        let lighting: LightingPreset
        let look: CaptureLook
        let title: String
    }

    /// Starts rendering the animation as video: objects move between keyframes while the
    /// camera glides between each keyframe's photo angle. Progress shows in `animaticProgress`.
    func startAnimatic(_ input: AnimaticInput, workspace: WorkspaceScene) {
        guard !isExporting else { return }
        animaticTask = Task { await renderAnimatic(input, workspace: workspace) }
    }

    func cancelAnimatic() {
        animaticTask?.cancel()
    }

    private func renderAnimatic(_ input: AnimaticInput, workspace: WorkspaceScene) async {
        let timeline = input.timeline
        let keyframed = timeline.keyframedObjectIDs

        isExporting = true
        exportError = nil
        exportedFile = nil
        animaticProgress = 0
        defer {
            isExporting = false
            animaticProgress = nil
            animaticTask = nil
        }

        let fps = Self.animaticFramesPerSecond
        let frameCount = Int((timeline.duration * Double(fps)).rounded(.up)) + 1
        let url = Self.exportURL(title: input.title, suffix: "Animatic", fileExtension: "mp4")
        var writer: VideoStreamWriter?
        do {
            let sequence = try await CompositionRenderer.Sequence(
                backdrop: workspace.backdrop, backdropPose: input.backdropPose, background: input.background,
                lighting: input.lighting, look: input.look,
                width: SlideshowExporter.width, height: SlideshowExporter.height)
            writer = try VideoStreamWriter(url: url, framesPerSecond: fps)

            var lastImage: CGImage?
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let time = min(Double(index) / Double(fps), timeline.duration)
                guard let frame = input.cameraPath.frame(at: time) else { continue }
                let snapshot = workspace.snapshot(at: timeline.poses(at: time), characterPoses: timeline.characterPoses(at: time),
                                                  keyframedObjects: keyframed)
                let image = try await sequence.render(snapshot: snapshot, frame: frame)
                try await writer?.append(image)
                lastImage = image
                animaticProgress = Double(index + 1) / Double(frameCount)
            }
            // Rest on the last shot for a moment.
            if let lastImage { try await writer?.append(lastImage, count: Int(fps) / 2) }
            try await writer?.finish()
            exportedFile = ExportedFile(url: url, shareTitle: "Share Animatic")
        } catch is CancellationError {
            writer?.cancel()
        } catch {
            writer?.cancel()
            exportError = "The animatic couldn't be rendered. \(error.localizedDescription)"
        }
    }

    // MARK: Storyboard sheet

    /// Exports a printable PDF: one numbered panel per keyframe with its primary photo
    /// (or an empty frame) and its notes.
    func exportStoryboardSheet(keyframes: [Keyframe], photos: PhotoLibrary, title: String) {
        guard !isExporting, !keyframes.isEmpty else { return }
        exportError = nil
        exportedFile = nil

        let panels = keyframes.enumerated().map { index, keyframe in
            StoryboardSheetExporter.Panel(
                number: index + 1,
                image: photos.primaryPhoto(for: keyframe.id).flatMap { photos.image(for: $0) },
                note: keyframe.note,
                shotType: keyframe.shotType
            )
        }
        let url = Self.exportURL(title: title, suffix: "Storyboard", fileExtension: "pdf")
        do {
            try StoryboardSheetExporter.export(title: title, panels: panels, layout: sheetLayout,
                                               includeNotes: sheetIncludesNotes, to: url)
            exportedFile = ExportedFile(url: url, shareTitle: "Share Storyboard Sheet")
        } catch {
            exportError = "The storyboard sheet couldn't be created."
        }
    }

    /// A temporary file named after the project, such as "Storyboard 2 Slideshow.mp4".
    private static func exportURL(title: String, suffix: String, fileExtension: String) -> URL {
        let safeName = title.replacingOccurrences(of: "/", with: "-")
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName) \(suffix).\(fileExtension)")
    }
}
