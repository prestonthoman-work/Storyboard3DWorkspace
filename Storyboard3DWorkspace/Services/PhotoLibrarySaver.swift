//
//  PhotoLibrarySaver.swift
//  Storyboard3DWorkspace
//

import Photos
import UIKit

/// Saves captured images to Photos using add-only access.
enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            "Storyboard 3D doesn't have permission to add to Photos. You can allow it in Settings."
        }
    }

    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.notAuthorized }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAsset(from: image)
        }
    }
}
