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
    /// Cut every export to the camera's frame shape (a real 9:16 vertical video, say)
    /// instead of 16:9 with black bars.
    var cropsToFrameShape: Bool = UserDefaults.standard.bool(forKey: "cropsToFrameShape") {
        didSet { UserDefaults.standard.set(cropsToFrameShape, forKey: "cropsToFrameShape") }
    }

    /// Lens blur in the animatic, when the camera has depth of field on. Fewer renders per
    /// frame than a photo, but still several times slower to export.
    var animaticDepthOfField: Bool = UserDefaults.standard.bool(forKey: "animaticDepthOfField") {
        didSet { UserDefaults.standard.set(animaticDepthOfField, forKey: "animaticDepthOfField") }
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
    /// - Parameter format: The project's frame shape, used when exports are cut to it.
    func exportSlideshow(keyframes: [Keyframe], photos: PhotoLibrary, title: String, format: FrameFormat = .widescreen) async {
        guard !isExporting else { return }
        let captions = slideshowCaptions
        let crops = cropsToFrameShape
        let labels = KeyframeTimeline(keyframes: keyframes).labels
        let slides: [CGImage] = keyframes.compactMap { keyframe in
            guard let photo = photos.primaryPhoto(for: keyframe.id), var image = photos.image(for: photo)?.cgImage
            else { return nil }
            if crops { image = Self.picture(of: image, format: photo.look.format) }
            guard captions else { return image }
            return SlideCaption.burn(SlideCaption.caption(shot: labels[keyframe.id]?.code ?? "", shotType: keyframe.shotType,
                                                          note: keyframe.note, camera: photo.cameraDetails), into: image)
        }
        guard !slides.isEmpty else { return }

        isExporting = true
        exportError = nil
        exportedFile = nil
        defer { isExporting = false }

        let url = Self.exportURL(title: title, suffix: "Slideshow", fileExtension: "mp4")
        let seconds = slideshowSecondsPerShot
        let crossfade = slideshowCrossfade
        let size = crops ? format.videoSize : (SlideshowExporter.width, SlideshowExporter.height)
        do {
            try await Task.detached(priority: .userInitiated) {
                try await SlideshowExporter.export(slides, secondsPerSlide: seconds, crossfade: crossfade, size: size, to: url)
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
        var walkers: Set<ObjectID> = []
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
        // Cut to the frame shape: render at full photo size so the picture inside the bars
        // keeps its detail, then crop each frame.
        let crops = cropsToFrameShape && input.look.format != .widescreen
        let renderSize = crops ? (FrameFormat.captureWidth, FrameFormat.captureHeight)
                               : (SlideshowExporter.width, SlideshowExporter.height)
        do {
            let sequence = try await CompositionRenderer.Sequence(
                backdrop: workspace.backdrop, backdropPose: input.backdropPose, background: input.background,
                lighting: input.lighting, look: input.look,
                width: renderSize.0, height: renderSize.1)
            writer = try VideoStreamWriter(url: url, framesPerSecond: fps,
                                           size: crops ? input.look.format.videoSize : (SlideshowExporter.width, SlideshowExporter.height))

            var lastImage: CGImage?
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let time = min(Double(index) / Double(fps), timeline.duration)
                guard let frame = input.cameraPath.frame(at: time) else { continue }
                let snapshot = workspace.snapshot(at: timeline.poses(at: time, walkers: input.walkers),
                                                  characterPoses: timeline.characterPoses(at: time, walkers: input.walkers),
                                                  keyframedObjects: keyframed, holds: timeline.heldProps(at: time))
                var image = try await sequence.render(snapshot: snapshot, frame: frame)
                if crops { image = Self.picture(of: image, format: input.look.format) }
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
    func exportStoryboardSheet(keyframes: [Keyframe], photos: PhotoLibrary, title: String, format: FrameFormat = .widescreen) {
        guard !isExporting, !keyframes.isEmpty else { return }
        exportError = nil
        exportedFile = nil

        let crops = cropsToFrameShape
        let labels = KeyframeTimeline(keyframes: keyframes).labels
        let panels = keyframes.map { keyframe in
            let photo = photos.primaryPhoto(for: keyframe.id)
            return StoryboardSheetExporter.Panel(
                label: labels[keyframe.id]?.code ?? "",
                image: photo.flatMap { photo in
                    photos.image(for: photo).map { image in
                        guard crops, let cgImage = image.cgImage else { return image }
                        return UIImage(cgImage: Self.picture(of: cgImage, format: photo.look.format))
                    }
                },
                note: keyframe.note,
                shotType: keyframe.shotType,
                camera: photo?.cameraDetails
            )
        }
        let url = Self.exportURL(title: title, suffix: "Storyboard", fileExtension: "pdf")
        do {
            try StoryboardSheetExporter.export(title: title, panels: panels, layout: sheetLayout,
                                               includeNotes: sheetIncludesNotes,
                                               imageAspect: crops ? CGFloat(format.aspect) : 16 / 9, to: url)
            exportedFile = ExportedFile(url: url, shareTitle: "Share Storyboard Sheet")
        } catch {
            exportError = "The storyboard sheet couldn't be created."
        }
    }

    /// The picture inside an image's bars, for exports cut to the frame shape.
    static func picture(of image: CGImage, format: FrameFormat) -> CGImage {
        guard format != .widescreen else { return image }
        return image.cropping(to: format.pictureRect(width: image.width, height: image.height)) ?? image
    }

    // MARK: Shot list

    /// One row per keyframe for a shot list or schedule: shot number, time, shot type,
    /// notes, the primary photo's camera settings and lighting, and who's in the shot.
    static func shotListCSV(keyframes: [Keyframe], photos: PhotoLibrary, objectNames: [ObjectID: String],
                            characterIDs: Set<ObjectID>) -> String {
        let header = ["Scene", "Shot", "Time (s)", "Shot Type", "Notes", "Lens", "Aperture", "Frame", "Lighting",
                      "Characters", "Objects", "Photo"]
        let timeline = KeyframeTimeline(keyframes: keyframes)
        let labels = timeline.labels
        let sceneTitles = Dictionary(uniqueKeysWithValues: timeline.scenes.map { ($0.number, $0.title) })
        let rows = keyframes.map { keyframe -> [String] in
            let label = labels[keyframe.id]
            let photo = photos.primaryPhoto(for: keyframe.id)
            let inShot = keyframe.poses.keys.compactMap { id in objectNames[id].map { (id, $0) } }
                .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            return [
                label.map { scene in
                    let title = sceneTitles[scene.scene] ?? ""
                    return title.isEmpty ? String(scene.scene) : "\(scene.scene) \(title)"
                } ?? "",
                label?.code ?? "",
                keyframe.time.formatted(.number.precision(.fractionLength(1))),
                keyframe.shotType?.name ?? "",
                keyframe.note.trimmingCharacters(in: .whitespacesAndNewlines),
                photo?.lens.label ?? "",
                photo?.look.depthOfField?.label ?? "",
                photo.map { "\($0.look.format.name) \($0.look.format.label)" } ?? "",
                photo?.lighting.name ?? "",
                inShot.filter { characterIDs.contains($0.0) }.map(\.1).joined(separator: ", "),
                inShot.filter { !characterIDs.contains($0.0) }.map(\.1).joined(separator: ", "),
                photo == nil ? "No" : "Yes",
            ]
        }
        return ([header] + rows).map { $0.map(csvField).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// A CSV field, quoted when it holds a comma, quote, or line break.
    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Exports the shot list as a CSV file that opens in Numbers, Excel, or Google Sheets.
    func exportShotList(keyframes: [Keyframe], photos: PhotoLibrary, objectNames: [ObjectID: String],
                        characterIDs: Set<ObjectID>, title: String) {
        guard !isExporting, !keyframes.isEmpty else { return }
        exportError = nil
        exportedFile = nil
        let url = Self.exportURL(title: title, suffix: "Shot List", fileExtension: "csv")
        do {
            let text = Self.shotListCSV(keyframes: keyframes, photos: photos, objectNames: objectNames,
                                        characterIDs: characterIDs)
            // A byte-order mark so spreadsheet apps read names with accents correctly.
            try Data(("\u{FEFF}" + text).utf8).write(to: url, options: .atomic)
            exportedFile = ExportedFile(url: url, shareTitle: "Share Shot List")
        } catch {
            exportError = "The shot list couldn't be created. \(error.localizedDescription)"
        }
    }

    /// A temporary file named after the project, such as "Storyboard 2 Slideshow.mp4".
    private static func exportURL(title: String, suffix: String, fileExtension: String) -> URL {
        let safeName = title.replacingOccurrences(of: "/", with: "-")
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName) \(suffix).\(fileExtension)")
    }
}
