//
//  PhotoLibrary.swift
//  Storyboard3DWorkspace
//

import SwiftUI
import UIKit

/// A rendered capture, optionally attached to the keyframe it was taken at.
struct CapturedPhoto: Identifiable {
    enum Assignment: Codable, Equatable {
        /// Taken while the scene matched this keyframe.
        case keyframe(Keyframe.ID)
        /// Taken while the scene didn't match any keyframe.
        case unassigned
        /// Was attached to a keyframe that has since been changed or deleted.
        case removed
    }

    var id = UUID()
    var takenAt = Date()
    let lens: CaptureLens
    /// Full-resolution image, JPEG-compressed to keep memory low.
    let jpegData: Data
    let thumbnail: UIImage
    var assignment: Assignment
    /// Where the camera was, so the photo can be retaken or re-rendered. Nil for photos
    /// taken before angles were saved.
    var camera: CaptureCamera?
    var lighting: LightingPreset = .studio
    /// Frame format and film grade, so a re-render is finished the same way.
    var look: CaptureLook = .plain
    /// Where the backdrop sat when the photo was taken, so a re-render matches.
    var backdropPose: CodableTransform?

    var keyframeID: Keyframe.ID? {
        if case .keyframe(let id) = assignment { id } else { nil }
    }
}

/// Every photo taken this session, plus which photo is primary for each keyframe.
///
/// Photos are never lost when a keyframe changes: they're detached and stay here,
/// marked as removed, so the Capture tab can still show them.
@Observable
final class PhotoLibrary {
    /// Oldest first.
    private(set) var photos: [CapturedPhoto] = []
    private(set) var primaryPhotoIDs: [Keyframe.ID: CapturedPhoto.ID] = [:]

    /// Every photo seen this session, including deleted ones, so undo can bring them back.
    @ObservationIgnored private(set) var archive: [CapturedPhoto.ID: CapturedPhoto] = [:]
    @ObservationIgnored private var decodedImages: [CapturedPhoto.ID: UIImage] = [:]
    @ObservationIgnored private var decodeOrder: [CapturedPhoto.ID] = []

    @discardableResult
    func add(_ image: CGImage, lens: CaptureLens, keyframe: Keyframe.ID?, camera: CaptureCamera? = nil,
             lighting: LightingPreset = .studio, look: CaptureLook = .plain,
             backdropPose: CodableTransform? = nil) -> CapturedPhoto? {
        guard let photo = makePhoto(image, lens: lens, assignment: keyframe.map { .keyframe($0) } ?? .unassigned,
                                    camera: camera, lighting: lighting, look: look, backdropPose: backdropPose)
        else { return nil }
        photos.append(photo)
        // A keyframe's first photo becomes its primary until another is chosen.
        if let keyframe, primaryPhotoIDs[keyframe] == nil {
            primaryPhotoIDs[keyframe] = photo.id
        }
        return photo
    }

    /// Swaps in a new render of a photo: same keyframe and primary status, new image.
    /// The old version stays in the archive so undo can bring it back.
    @discardableResult
    func replace(_ old: CapturedPhoto, with image: CGImage, camera: CaptureCamera? = nil,
                 lighting: LightingPreset? = nil, look: CaptureLook? = nil) -> CapturedPhoto? {
        guard let index = photos.firstIndex(where: { $0.id == old.id }) else { return nil }
        let newCamera = camera ?? old.camera
        guard let photo = makePhoto(image, lens: newCamera?.lens ?? old.lens, assignment: old.assignment,
                                    camera: newCamera, lighting: lighting ?? old.lighting,
                                    look: look ?? old.look, backdropPose: old.backdropPose)
        else { return nil }
        photos[index] = photo
        if let keyframe = old.keyframeID, primaryPhotoIDs[keyframe] == old.id {
            primaryPhotoIDs[keyframe] = photo.id
        }
        return photo
    }

    /// Detaches one photo from its keyframe (it stays in the library).
    func detach(_ photo: CapturedPhoto) {
        guard let index = photos.firstIndex(where: { $0.id == photo.id }), let keyframe = photos[index].keyframeID else { return }
        photos[index].assignment = .removed
        if primaryPhotoIDs[keyframe] == photo.id {
            primaryPhotoIDs[keyframe] = photos(for: keyframe).first?.id
        }
    }

    private func makePhoto(_ image: CGImage, lens: CaptureLens, assignment: CapturedPhoto.Assignment,
                           camera: CaptureCamera?, lighting: LightingPreset, look: CaptureLook,
                           backdropPose: CodableTransform?) -> CapturedPhoto? {
        let full = UIImage(cgImage: image)
        guard let data = full.jpegData(compressionQuality: 0.92) else { return nil }
        let photo = CapturedPhoto(lens: lens, jpegData: data, thumbnail: Self.makeThumbnail(full),
                                  assignment: assignment, camera: camera, lighting: lighting,
                                  look: look, backdropPose: backdropPose)
        archive[photo.id] = photo
        remember(full, for: photo.id)
        return photo
    }

    /// Empties the library when switching projects.
    func reset() {
        photos = []
        primaryPhotoIDs = [:]
        archive = [:]
        decodedImages = [:]
        decodeOrder = []
    }

    /// Adds photos read from disk.
    func load(_ loaded: [CapturedPhoto], primaries: [Keyframe.ID: CapturedPhoto.ID]) {
        for photo in loaded { archive[photo.id] = photo }
        photos = loaded
        primaryPhotoIDs = primaries
    }

    /// Restores which photos exist and how they're attached (undo). Photos are looked up
    /// in the archive, so deleted ones come back with their images.
    func restore(_ entries: [(id: CapturedPhoto.ID, assignment: CapturedPhoto.Assignment)],
                 primaries: [Keyframe.ID: CapturedPhoto.ID]) {
        photos = entries.compactMap { entry in
            guard var photo = archive[entry.id] else { return nil }
            photo.assignment = entry.assignment
            return photo
        }
        let existing = Set(photos.map(\.id))
        primaryPhotoIDs = primaries.filter { existing.contains($0.value) }
    }

    func photo(_ id: CapturedPhoto.ID?) -> CapturedPhoto? {
        photos.first { $0.id == id }
    }

    func photos(for keyframe: Keyframe.ID) -> [CapturedPhoto] {
        photos.filter { $0.keyframeID == keyframe }
    }

    func primaryPhoto(for keyframe: Keyframe.ID) -> CapturedPhoto? {
        photo(primaryPhotoIDs[keyframe])
    }

    func isPrimary(_ photo: CapturedPhoto) -> Bool {
        guard let keyframe = photo.keyframeID else { return false }
        return primaryPhotoIDs[keyframe] == photo.id
    }

    func setPrimary(_ photo: CapturedPhoto) {
        guard let keyframe = photo.keyframeID else { return }
        primaryPhotoIDs[keyframe] = photo.id
    }

    /// The keyframe changed or was deleted: its photos no longer represent it.
    func detachPhotos(from keyframe: Keyframe.ID) {
        for index in photos.indices where photos[index].keyframeID == keyframe {
            photos[index].assignment = .removed
        }
        primaryPhotoIDs[keyframe] = nil
    }

    func delete(_ photo: CapturedPhoto) {
        photos.removeAll { $0.id == photo.id }
        decodedImages[photo.id] = nil
        decodeOrder.removeAll { $0 == photo.id }
        if let keyframe = photo.keyframeID, primaryPhotoIDs[keyframe] == photo.id {
            primaryPhotoIDs[keyframe] = photos(for: keyframe).first?.id
        }
    }

    /// The full-resolution image. A few recently viewed images stay decoded.
    func image(for photo: CapturedPhoto) -> UIImage? {
        if let cached = decodedImages[photo.id] { return cached }
        guard let image = UIImage(data: photo.jpegData) else { return nil }
        remember(image, for: photo.id)
        return image
    }

    private func remember(_ image: UIImage, for id: CapturedPhoto.ID) {
        decodedImages[id] = image
        decodeOrder.removeAll { $0 == id }
        decodeOrder.append(id)
        while decodeOrder.count > 4 {
            decodedImages[decodeOrder.removeFirst()] = nil
        }
    }

    private static func makeThumbnail(_ image: UIImage) -> UIImage {
        let size = CGSize(width: 480, height: 270)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
