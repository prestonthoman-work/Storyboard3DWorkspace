//
//  ProjectStore.swift
//  Storyboard3DWorkspace
//

import Foundation
import UIKit

/// Saves projects to the app's Application Support folder and reads them back.
///
/// Layout, one folder per project under `Projects/<id>/`:
/// - `info.json`: name, last edited, and cover photo, for the project list
/// - `project.json`: the `ProjectState`, the lens, and which backdrop is in use
/// - `photos/<id>.jpg` and `photos/<id>-thumb.jpg`: each photo and its thumbnail
/// - `backdrop-<id>.jpg`: an imported backdrop image (the built-in sky isn't stored)
/// - `models/<id>.usdz`: each imported 3D model, named by its recipe's file ID
enum ProjectStore {
    struct Info: Codable, Identifiable, Equatable {
        var id: UUID
        var name: String
        var modified: Date
        /// The photo shown for this project in the list.
        var coverPhotoID: UUID?
        /// Number of keyframes (shots), for the gallery. Optional for older projects.
        var shotCount: Int?
    }

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
        var captureLighting: LightingPreset?
        /// Optional so projects saved before looks existed still load.
        var captureLook: CaptureLook?
        var backdrop: Backdrop?
    }

    struct LoadedProject {
        var saved: SavedProject
        var photos: [CapturedPhoto]
        /// Photos listed in the project whose image files couldn't be read. They can't be
        /// shown, but callers should keep them in the saved file so they aren't erased.
        var missingPhotos: [ProjectState.Photo] = []
        var backdropImage: CGImage?
    }

    /// Where projects live. Tests point this at a temporary folder so they never touch
    /// real projects; the app leaves it nil (Application Support).
    static var storageOverride: URL?

    private static var storage: URL { storageOverride ?? URL.applicationSupportDirectory }
    /// The folder that holds the project list and app-wide files such as saved poses.
    static var storageRoot: URL { storage }
    private static var root: URL {
        storage.appending(path: "Projects", directoryHint: .isDirectory)
    }
    private static func folder(_ project: UUID) -> URL {
        root.appending(path: project.uuidString, directoryHint: .isDirectory)
    }
    private static func infoFile(_ project: UUID) -> URL { folder(project).appending(path: "info.json") }
    private static func projectFile(_ project: UUID) -> URL { folder(project).appending(path: "project.json") }
    private static func photosFolder(_ project: UUID) -> URL {
        folder(project).appending(path: "photos", directoryHint: .isDirectory)
    }
    private static func photoFile(_ project: UUID, _ photo: UUID, thumbnail: Bool = false) -> URL {
        photosFolder(project).appending(path: "\(photo.uuidString)\(thumbnail ? "-thumb" : "").jpg")
    }
    private static func backdropFile(_ project: UUID, _ file: UUID) -> URL {
        folder(project).appending(path: "backdrop-\(file.uuidString).jpg")
    }
    private static func modelsFolder(_ project: UUID) -> URL {
        folder(project).appending(path: "models", directoryHint: .isDirectory)
    }
    /// Where an imported model is stored.
    static func modelFile(_ project: UUID, _ file: UUID) -> URL {
        modelsFolder(project).appending(path: "\(file.uuidString).usdz")
    }

    // MARK: Project list

    /// Every project, most recently edited first.
    static func list() -> [Info] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders
            .compactMap { try? Data(contentsOf: $0.appending(path: "info.json")) }
            .compactMap { try? JSONDecoder().decode(Info.self, from: $0) }
            .sorted { $0.modified > $1.modified }
    }

    static func create(name: String) throws -> Info {
        let info = Info(id: UUID(), name: name, modified: .now, coverPhotoID: nil)
        try FileManager.default.createDirectory(at: folder(info.id), withIntermediateDirectories: true)
        try write(info)
        return info
    }

    static func rename(_ project: UUID, to name: String) throws {
        guard var info = (try? Data(contentsOf: infoFile(project))).flatMap({ try? JSONDecoder().decode(Info.self, from: $0) })
        else { throw CocoaError(.fileReadNoSuchFile) }
        info.name = name
        try write(info)
    }

    /// Copies a project, with all its photos and backdrop, under a new name.
    static func duplicate(_ project: UUID, name: String) throws -> Info {
        guard var info = (try? Data(contentsOf: infoFile(project))).flatMap({ try? JSONDecoder().decode(Info.self, from: $0) })
        else { throw CocoaError(.fileReadNoSuchFile) }
        info.id = UUID()
        info.name = name
        info.modified = .now
        try FileManager.default.copyItem(at: folder(project), to: folder(info.id))
        try write(info)
        return info
    }

    static func delete(_ project: UUID) throws {
        try FileManager.default.removeItem(at: folder(project))
    }

    static func coverThumbnail(for info: Info) -> UIImage? {
        guard let photo = info.coverPhotoID else { return nil }
        return (try? Data(contentsOf: photoFile(info.id, photo, thumbnail: true))).flatMap(UIImage.init(data:))
    }

    private static func write(_ info: Info) throws {
        try JSONEncoder().encode(info).write(to: infoFile(info.id), options: .atomic)
    }

    /// Earlier versions kept a single project in `StoryboardProject/`. Moves it into the
    /// project list so nothing is lost. If the move fails, the old folder is left where it
    /// is, so it can be tried again on the next call.
    static func migrateLegacyProjectIfNeeded() throws {
        let files = FileManager.default
        let legacy = storage.appending(path: "StoryboardProject", directoryHint: .isDirectory)
        guard files.fileExists(atPath: legacy.appending(path: "project.json").path(percentEncoded: false)) else { return }

        let id = UUID()
        let modified = (try? files.attributesOfItem(atPath: legacy.appending(path: "project.json").path(percentEncoded: false))[.modificationDate]) as? Date
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        try files.moveItem(at: legacy, to: folder(id))
        try write(Info(id: id, name: "My Storyboard", modified: modified ?? .now, coverPhotoID: nil))
    }

    // MARK: Saving

    /// Writes a project. Image files are written only when missing, and files for photos
    /// or backdrops no longer in the project are removed.
    static func save(_ info: Info, project: SavedProject, photos: [CapturedPhoto], backdropImage: CGImage?) throws {
        let files = FileManager.default
        let id = info.id
        try files.createDirectory(at: photosFolder(id), withIntermediateDirectories: true)

        // Keep the files of every photo the project lists, including ones that couldn't be
        // read when it was opened, in case they come back.
        var keep = Set<String>()
        for entry in project.state.photos {
            keep.formUnion([photoFile(id, entry.id).lastPathComponent,
                            photoFile(id, entry.id, thumbnail: true).lastPathComponent])
        }
        for photo in photos {
            let full = photoFile(id, photo.id)
            let thumbnail = photoFile(id, photo.id, thumbnail: true)
            keep.formUnion([full.lastPathComponent, thumbnail.lastPathComponent])
            if !files.fileExists(atPath: full.path(percentEncoded: false)) {
                try photo.jpegData.write(to: full, options: .atomic)
            }
            if !files.fileExists(atPath: thumbnail.path(percentEncoded: false)), let data = photo.thumbnail.jpegData(compressionQuality: 0.8) {
                try data.write(to: thumbnail, options: .atomic)
            }
        }
        for name in (try? files.contentsOfDirectory(atPath: photosFolder(id).path(percentEncoded: false))) ?? [] where !keep.contains(name) {
            try? files.removeItem(at: photosFolder(id).appending(path: name))
        }

        let backdropName = project.backdrop?.fileID.map { backdropFile(id, $0).lastPathComponent }
        if let fileID = project.backdrop?.fileID, let backdropImage,
           !files.fileExists(atPath: backdropFile(id, fileID).path(percentEncoded: false)),
           let data = UIImage(cgImage: backdropImage).jpegData(compressionQuality: 0.9) {
            try data.write(to: backdropFile(id, fileID), options: .atomic)
        }
        for name in (try? files.contentsOfDirectory(atPath: folder(id).path(percentEncoded: false))) ?? []
        where name.hasPrefix("backdrop-") && name != backdropName {
            try? files.removeItem(at: folder(id).appending(path: name))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(project).write(to: projectFile(id), options: .atomic)
        try write(info)
    }

    // MARK: Imported models

    /// Copies a model file into the project. Returns the ID it's stored under.
    static func importModel(from source: URL, into project: UUID) throws -> UUID {
        let id = UUID()
        try FileManager.default.createDirectory(at: modelsFolder(project), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: modelFile(project, id))
        return id
    }

    static func removeModel(_ file: UUID, from project: UUID) {
        try? FileManager.default.removeItem(at: modelFile(project, file))
    }

    /// Deletes stored models the project doesn't use. Call only when opening a project: while
    /// it's open, undo can bring back a deleted object, and it needs its model file.
    static func removeUnusedModels(in project: UUID, keeping used: Set<UUID>) {
        let keep = Set(used.map { modelFile(project, $0).lastPathComponent })
        let folder = modelsFolder(project)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        where !keep.contains(name) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    // MARK: Loading

    /// A saved project, or nil if it has never been saved.
    ///
    /// Throws if the project file exists but can't be read or decoded, so a damaged
    /// project is never mistaken for an empty one (and then saved over).
    static func load(_ project: UUID) throws -> LoadedProject? {
        let file = projectFile(project)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
        let saved = try JSONDecoder().decode(SavedProject.self, from: Data(contentsOf: file))

        // Photos whose image files are missing aren't shown blank; they're reported instead.
        var missing: [ProjectState.Photo] = []
        let photos: [CapturedPhoto] = saved.state.photos.compactMap { entry in
            guard let jpeg = try? Data(contentsOf: photoFile(project, entry.id)),
                  let thumbnail = (try? Data(contentsOf: photoFile(project, entry.id, thumbnail: true))).flatMap(UIImage.init(data:))
                    ?? UIImage(data: jpeg)
            else {
                missing.append(entry)
                return nil
            }
            return CapturedPhoto(id: entry.id, takenAt: entry.takenAt, lens: entry.lens,
                                 jpegData: jpeg, thumbnail: thumbnail, assignment: entry.assignment,
                                 camera: entry.camera, lighting: entry.lighting ?? .studio,
                                 look: entry.look ?? .plain, backdropPose: entry.backdropPose)
        }

        let backdropImage = saved.backdrop?.fileID
            .flatMap { try? Data(contentsOf: backdropFile(project, $0)) }
            .flatMap { UIImage(data: $0)?.cgImage }

        return LoadedProject(saved: saved, photos: photos, missingPhotos: missing, backdropImage: backdropImage)
    }
}
