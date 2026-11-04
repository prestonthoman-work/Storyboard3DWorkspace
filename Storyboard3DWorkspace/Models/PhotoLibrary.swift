//
//  PhotoLibrary.swift
//  Storyboard3DWorkspace
//

import SwiftUI
import UIKit

/// A rendered capture, optionally attached to the keyframe it was taken at.
struct CapturedPhoto: Identifiable {
    enum Assignment: Equatable {
        /// Taken while the scene matched this keyframe.
        case keyframe(Keyframe.ID)
        /// Taken while the scene didn't match any keyframe.
        case unassigned
        /// Was attached to a keyframe that has since been changed or deleted.
        case removed
    }

    let id = UUID()
    let takenAt = Date()
    let lens: CaptureLens
    /// Full-resolution image, JPEG-compressed to keep memory low.
    let jpegData: Data
    let thumbnail: UIImage
    var assignment: Assignment

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

    @ObservationIgnored private var decodedImages: [CapturedPhoto.ID: UIImage] = [:]
    @ObservationIgnored private var decodeOrder: [CapturedPhoto.ID] = []

    @discardableResult
    func add(_ image: CGImage, lens: CaptureLens, keyframe: Keyframe.ID?) -> CapturedPhoto? {
        let full = UIImage(cgImage: image)
        guard let data = full.jpegData(compressionQuality: 0.92) else { return nil }

        let photo = CapturedPhoto(
            lens: lens,
            jpegData: data,
            thumbnail: Self.makeThumbnail(full),
            assignment: keyframe.map { .keyframe($0) } ?? .unassigned
        )
        photos.append(photo)
        // A keyframe's first photo becomes its primary until another is chosen.
        if let keyframe, primaryPhotoIDs[keyframe] == nil {
            primaryPhotoIDs[keyframe] = photo.id
        }
        remember(full, for: photo.id)
        return photo
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
