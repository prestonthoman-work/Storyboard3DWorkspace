//
//  ProjectStore.swift
//  Storyboard3DWorkspace
//

import Foundation
import UIKit

/// Saves the project to the app's Application Support folder and reads it back at launch.
///
/// Layout:
/// - `project.json`: the `ProjectState`, the lens, and which backdrop is in use
/// - `photos/<id>.jpg` and `photos/<id>-thumb.jpg`: each photo and its thumbnail
/// - `backdrop-<id>.jpg`: an imported backdrop image (the built-in sky isn't stored)
enum ProjectStore {
    struct SavedProject: Codable {
        struct Backdrop: Codable, Equatable {
            var name: String
            var source: BackdropImage.Source
            /// Names the stored image file; nil for the built-in sky.
            var fileID: UUID?
        }

        var version = 1
        var state: ProjectState
        var captureLens: CaptureLens
        var backdrop: Backdrop?
    }

    struct LoadedProject {
        var saved: SavedProject
        var photos: [CapturedPhoto]
        var backdropImage: CGImage?
    }

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "StoryboardProject", directoryHint: .isDirectory)
    }
    private static var photosFolder: URL { folder.appending(path: "photos", directoryHint: .isDirectory) }
    private static var projectFile: URL { folder.appending(path: "project.json") }

    private static func photoFile(_ id: UUID, thumbnail: Bool = false) -> URL {
        photosFolder.appending(path: "\(id.uuidString)\(thumbnail ? "-thumb" : "").jpg")
    }

    private static func backdropFile(_ id: UUID) -> URL {
        folder.appending(path: "backdrop-\(id.uuidString).jpg")
    }

    // MARK: Saving

    /// Writes the project. Image files are written only when missing, and files for photos
    /// or backdrops no longer in the project are removed.
    static func save(_ project: SavedProject, photos: [CapturedPhoto], backdropImage: CGImage?) throws {
        let files = FileManager.default
        try files.createDirectory(at: photosFolder, withIntermediateDirectories: true)

        var keep = Set<String>()
        for photo in photos {
            let full = photoFile(photo.id)
            let thumbnail = photoFile(photo.id, thumbnail: true)
            keep.formUnion([full.lastPathComponent, thumbnail.lastPathComponent])
            if !files.fileExists(atPath: full.path()) {
                try photo.jpegData.write(to: full, options: .atomic)
            }
            if !files.fileExists(atPath: thumbnail.path()), let data = photo.thumbnail.jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbnail, options: .atomic)
            }
        }
        for name in (try? files.contentsOfDirectory(atPath: photosFolder.path())) ?? [] where !keep.contains(name) {
            try? files.removeItem(at: photosFolder.appending(path: name))
        }

        let backdropName = project.backdrop?.fileID.map { backdropFile($0).lastPathComponent }
        if let fileID = project.backdrop?.fileID, let backdropImage,
           !files.fileExists(atPath: backdropFile(fileID).path()),
           let data = UIImage(cgImage: backdropImage).jpegData(compressionQuality: 0.9) {
            try data.write(to: backdropFile(fileID), options: .atomic)
        }
        for name in (try? files.contentsOfDirectory(atPath: folder.path())) ?? []
        where name.hasPrefix("backdrop-") && name != backdropName {
            try? files.removeItem(at: folder.appending(path: name))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(project).write(to: projectFile, options: .atomic)
    }

    // MARK: Loading

    /// The saved project, or nil if there isn't one (or it can't be read).
    static func load() -> LoadedProject? {
        guard let data = try? Data(contentsOf: projectFile),
              let saved = try? JSONDecoder().decode(SavedProject.self, from: data)
        else { return nil }

        // Photos whose image files are missing are dropped rather than shown blank.
        let photos: [CapturedPhoto] = saved.state.photos.compactMap { entry in
            guard let jpeg = try? Data(contentsOf: photoFile(entry.id)) else { return nil }
            let thumbnail = (try? Data(contentsOf: photoFile(entry.id, thumbnail: true))).flatMap(UIImage.init(data:))
                ?? UIImage(data: jpeg)
            guard let thumbnail else { return nil }
            return CapturedPhoto(id: entry.id, takenAt: entry.takenAt, lens: entry.lens,
                                 jpegData: jpeg, thumbnail: thumbnail, assignment: entry.assignment)
        }

        let backdropImage = saved.backdrop?.fileID
            .flatMap { try? Data(contentsOf: backdropFile($0)) }
            .flatMap { UIImage(data: $0)?.cgImage }

        return LoadedProject(saved: saved, photos: photos, backdropImage: backdropImage)
    }
}
