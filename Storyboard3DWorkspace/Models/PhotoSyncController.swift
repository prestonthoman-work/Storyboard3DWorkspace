//
//  PhotoSyncController.swift
//  Storyboard3DWorkspace
//

import CoreGraphics
import Foundation
import RealityKit

/// Keeps keyframe photos showing their keyframes. When a keyframe's content changes, its
/// photos are re-rendered from their saved angles, or, when that's off or impossible (photos
/// taken before angles were saved), moved to the library.
///
/// `AppModel` owns one and hands it the changed keyframes; it gets back what changed and
/// updates its selection, notices, and saving, so this type never reaches back into the project.
@MainActor
@Observable
final class PhotoSyncController {
    private let workspace: WorkspaceScene
    private let photos: PhotoLibrary

    init(workspace: WorkspaceScene, photos: PhotoLibrary) {
        self.workspace = workspace
        self.photos = photos
    }

    /// Re-render photos when their keyframe changes, instead of moving them to the library.
    /// Remembered across launches.
    var isOn: Bool = UserDefaults.standard.object(forKey: "keepPhotosInSync") as? Bool ?? true {
        didSet { UserDefaults.standard.set(isOn, forKey: "keepPhotosInSync") }
    }

    /// True while photos are being re-rendered.
    private(set) var isUpdating = false

    /// A photo to re-render, with a snapshot of its keyframe taken when it changed.
    struct Job {
        let photo: CapturedPhoto
        let snapshot: Entity
    }

    /// Photos moved to the library because they couldn't be re-rendered, by keyframe.
    typealias Detached = [(keyframe: Keyframe.ID, count: Int)]

    /// Snapshots each changed keyframe right away (before anything else can change) and lists
    /// the photos to re-render. Photos that can't be re-rendered are detached now.
    /// - Parameter canRender: False when there's no backdrop to render with.
    func prepare(_ keyframeIDs: [Keyframe.ID], timeline: KeyframeTimeline, canRender: Bool) -> (jobs: [Job], detached: Detached) {
        var jobs: [Job] = []
        var detached: Detached = []
        for id in keyframeIDs {
            let affected = photos.photos(for: id)
            guard !affected.isEmpty else { continue }
            guard isOn, canRender, let keyframe = timeline.keyframe(id) else {
                photos.detachPhotos(from: id)
                detached.append((id, affected.count))
                continue
            }
            let snapshot = workspace.snapshot(at: keyframe.poses, characterPoses: keyframe.characterPoses,
                                              keyframedObjects: timeline.keyframedObjectIDs,
                                              holds: timeline.heldProps(at: keyframe.time))
            for photo in affected {
                if photo.camera != nil {
                    jobs.append(Job(photo: photo, snapshot: snapshot))
                } else {
                    photos.detach(photo)
                }
            }
        }
        return (jobs, detached)
    }

    /// Re-renders each photo from its saved angle, lighting, and look, replacing it in the
    /// library. Photos deleted or detached since the change are skipped.
    /// - Returns: Each replaced photo's old and new ID.
    func rerender(_ jobs: [Job], background: CGImage) async -> [(old: CapturedPhoto.ID, new: CapturedPhoto.ID)] {
        isUpdating = true
        defer { isUpdating = false }
        var replaced: [(old: CapturedPhoto.ID, new: CapturedPhoto.ID)] = []
        for job in jobs {
            let photo = job.photo
            guard let camera = photo.camera, photos.photo(photo.id)?.keyframeID == photo.keyframeID,
                  let image = try? await CompositionRenderer().render(
                    snapshot: job.snapshot, backdrop: workspace.backdrop, backdropPose: photo.backdropPose?.transform,
                    background: background, camera: camera, lighting: photo.lighting, look: photo.look),
                  let replacement = photos.replace(photo, with: image)
            else { continue }
            replaced.append((photo.id, replacement.id))
        }
        return replaced
    }
}
