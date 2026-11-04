//
//  BackdropImageLoader.swift
//  Storyboard3DWorkspace
//

import UIKit

/// Prepares imported image data for use as a backdrop texture.
nonisolated enum BackdropImageLoader {
    enum LoadError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "That file couldn't be read as an image."
        }
    }

    /// Redraws the image upright (applying EXIF orientation) and caps its size so it
    /// stays within comfortable texture limits.
    static func prepare(_ data: Data, maxDimension: CGFloat = 4096) throws -> CGImage {
        guard let image = UIImage(data: data) else { throw LoadError.unreadable }

        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > 0 else { throw LoadError.unreadable }

        let factor = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: (pixelSize.width * factor).rounded(.down),
                                height: (pixelSize.height * factor).rounded(.down))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let cgImage = rendered.cgImage else { throw LoadError.unreadable }
        return cgImage
    }

    static func prepare(fileAt url: URL) throws -> CGImage {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return try prepare(Data(contentsOf: url))
    }
}
