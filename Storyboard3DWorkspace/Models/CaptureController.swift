//
//  CaptureController.swift
//  Storyboard3DWorkspace
//

import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// The capture camera: its settings (lens, frame and lens blur, lighting), the self-timer,
/// what the last capture did, and rendering photos of the scene.
///
/// `AppModel` owns one. It decides which keyframe a photo belongs to and wraps each capture in
/// undo and saving, so this type never reaches back into the project, the photo library, or
/// the undo history: it renders and reports, and `AppModel` files the result.
@MainActor
@Observable
final class CaptureController {
    enum Status: Hashable {
        case attached(keyframeNumber: Int)
        case libraryOnly
        case retaken(keyframeNumber: Int)
        case saved
        case failed(String)
    }

    private let workspace: WorkspaceScene

    init(workspace: WorkspaceScene) {
        self.workspace = workspace
    }

    // MARK: Settings

    var lens: CaptureLens = .standard {
        didSet { refreshViewfinder() }
    }

    /// Frame shape, lens blur, and film grade for new captures.
    var look: CaptureLook = .standard {
        didSet { if look != oldValue { refreshViewfinder() } }
    }

    var lighting: LightingPreset = .studio {
        didSet { if lighting != oldValue { refreshLightingPreview() } }
    }

    /// Light the diorama in the headset with the capture lighting, instead of the room's.
    /// Remembered across launches.
    var isLightingPreviewOn: Bool = UserDefaults.standard.bool(forKey: "isLightingPreviewOn") {
        didSet {
            UserDefaults.standard.set(isLightingPreviewOn, forKey: "isLightingPreviewOn")
            refreshLightingPreview()
        }
    }

    /// Whether the scene is showing in the room. The lighting preview only applies there.
    var isSpaceOpen = false {
        didSet { if isSpaceOpen != oldValue { refreshLightingPreview() } }
    }

    private func refreshViewfinder() {
        workspace.setViewfinder(lens: lens, format: look.format)
    }

    /// Applies (or removes) the in-headset lighting preview to match the settings.
    func refreshLightingPreview() {
        let preset = isLightingPreviewOn && isSpaceOpen ? lighting : nil
        let camera = viewerCamera()
        Task { await workspace.setLightingPreview(preset, camera: camera) }
    }

    /// A camera where the viewer is standing, looking where they look.
    func viewerCamera() -> CaptureCamera {
        if let head = SpatialTrackingService.shared.viewerTransform {
            return .level(fromHead: head, lens: lens)
        }
        // No head tracking (such as in Simulator): look at the base from a standing position.
        return .looking(from: SpatialTrackingService.fallbackViewerPosition,
                        at: workspace.baseAnchor.position(relativeTo: nil), lens: lens)
    }

    // MARK: Status

    private(set) var isCapturing = false
    private(set) var isSavingToPhotos = false
    private(set) var isRenderingPreview = false
    /// What the last capture did, shown under the shutter.
    var status: Status?
    /// Seconds left on the self-timer, or nil when no countdown is running.
    private(set) var countdown: Int?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    var isBusy: Bool { isCapturing || countdown != nil }

    // MARK: Self-timer

    /// Counts down 3, 2, 1 (giving the viewer time to look away from the panel and back at
    /// their scene), then runs `shutter`.
    func startCountdown(then shutter: @escaping @MainActor () async -> Void) {
        guard !isBusy else { return }
        status = nil
        countdownTask = Task { [weak self] in
            for remaining in [3, 2, 1] {
                self?.countdown = remaining
                self?.workspace.playInterfaceSound(.tick, gain: -12)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.countdown = nil
            await shutter()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    // MARK: Rendering

    /// A photo just rendered, with everything needed to file it and render it again.
    struct Shot {
        let image: CGImage
        let camera: CaptureCamera
        let lens: CaptureLens
        let lighting: LightingPreset
        let look: CaptureLook
        /// Where the backdrop was, so this exact shot can be rendered again later.
        let backdropPose: CodableTransform
    }

    /// Photographs the scene as it is now, from where the viewer stands, with the current
    /// settings: a flash and shutter sound, then the render.
    func shoot(background: CGImage) async throws -> Shot {
        isCapturing = true
        defer { isCapturing = false }
        let camera = viewerCamera()
        workspace.flashViewfinder()
        workspace.playInterfaceSound(.shutter, gain: -4)
        let backdropPose = CodableTransform(Transform(matrix: workspace.backdrop.transformMatrix(relativeTo: nil)))
        let image = try await CompositionRenderer().render(
            snapshot: CompositionRenderer.snapshot(of: workspace.baseAnchor),
            backdrop: workspace.backdrop, backdropPose: nil, background: background,
            camera: camera, lighting: lighting, look: look)
        return Shot(image: image, camera: camera, lens: lens, lighting: lighting, look: look, backdropPose: backdropPose)
    }

    /// Re-shoots a saved angle of a posed scene (from `WorkspaceScene.snapshot(at:)`) with the
    /// current lens, lighting, and look.
    func retake(_ snapshot: Entity, from camera: CaptureCamera, backdropPose: Transform?,
                background: CGImage) async throws -> (image: CGImage, camera: CaptureCamera) {
        isCapturing = true
        defer { isCapturing = false }
        var camera = camera
        camera.lens = lens
        let image = try await CompositionRenderer().render(
            snapshot: snapshot, backdrop: workspace.backdrop, backdropPose: backdropPose,
            background: background, camera: camera, lighting: lighting, look: look)
        return (image, camera)
    }

    /// A small render from where the viewer stands with the current settings, so lens blur
    /// and the frame shape can be checked before taking the photo. Nil if it can't render.
    func renderPreview(background: CGImage) async -> UIImage? {
        guard !isRenderingPreview else { return nil }
        isRenderingPreview = true
        defer { isRenderingPreview = false }
        let image = try? await CompositionRenderer().render(
            snapshot: CompositionRenderer.snapshot(of: workspace.baseAnchor),
            backdrop: workspace.backdrop, backdropPose: nil, background: background,
            camera: viewerCamera(), lighting: lighting, look: look,
            width: CompositionRenderer.previewWidth, height: CompositionRenderer.previewHeight)
        return image.map(UIImage.init(cgImage:))
    }

    /// Saves an image to the person's Photos library, reporting the result in `status`.
    func saveToPhotos(_ image: UIImage) async {
        guard !isSavingToPhotos else { return }
        isSavingToPhotos = true
        defer { isSavingToPhotos = false }
        do {
            try await PhotoLibrarySaver.save(image)
            status = .saved
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
