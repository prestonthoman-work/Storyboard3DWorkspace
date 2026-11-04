//
//  BackdropImage.swift
//  Storyboard3DWorkspace
//

import UIKit

/// The 2D image currently shown on the viewer-facing backdrop.
struct BackdropImage {
    enum Source: String, Codable {
        case builtInSky
        case photos
        case files

        var label: String {
            switch self {
            case .builtInSky: "Built-in"
            case .photos: "From Photos"
            case .files: "From Files"
            }
        }
    }

    let name: String
    let source: Source
    let image: CGImage
    let preview: UIImage

    init(name: String, source: Source, image: CGImage) {
        self.name = name
        self.source = source
        self.image = image
        self.preview = UIImage(cgImage: image)
    }
}
