//
//  CatalogThumbnailTests.swift
//  Storyboard3DWorkspaceTests
//

import Foundation
import Testing
import UIKit
@testable import Storyboard3DWorkspace

@MainActor
struct CatalogThumbnailTests {
    @Test func everyCatalogObjectHasABundledThumbnail() {
        let thumbnails = CatalogThumbnails()
        thumbnails.loadIfNeeded()
        for kind in SampleObjectCatalog.Kind.allCases {
            #expect(thumbnails.images[kind] != nil, "Missing thumbnail for \(kind)")
        }
    }

    /// Re-renders the bundled library images into the source folder. Disabled normally;
    /// enable it after changing how a catalog object looks, run it once, then disable it.
    @Test(.disabled("Run by hand to regenerate Resources/Thumbnails"))
    func regenerateBundledThumbnails() async throws {
        let folder = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Storyboard3DWorkspace/Resources/Thumbnails")
        for kind in SampleObjectCatalog.Kind.allCases {
            let image = try await CatalogThumbnails.render(kind)
            let data = try #require(UIImage(cgImage: image).pngData())
            try data.write(to: folder.appending(path: CatalogThumbnails.resourceName(for: kind) + ".png"))
        }
    }
}
