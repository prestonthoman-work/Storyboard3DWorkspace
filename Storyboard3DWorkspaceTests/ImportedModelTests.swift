//
//  ImportedModelTests.swift
//  Storyboard3DWorkspaceTests
//

import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

private final class BundleToken {}

extension SharedStateTests {
    /// Importing USDZ files as objects. Each test uses its own temporary storage folder.
    /// `TallBox.usdz` is a box 0.5 × 2 × 1 m, centered well away from its file's origin.
    @MainActor
    @Suite(.serialized)
    struct ImportedModelTests {
        let storage: URL

        init() throws {
            storage = FileManager.default.temporaryDirectory.appending(path: "ImportedModelTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            ProjectStore.storageOverride = storage
            ImportedModels.keepOnly([])
        }

        private func makeApp() async throws -> AppModel {
            let app = AppModel()
            await app.createProject()
            _ = try #require(app.currentProject)
            return app
        }

        private func tallBox() throws -> URL {
            let bundle = Bundle(for: BundleToken.self)
            return try #require(bundle.url(forResource: "TallBox", withExtension: "usdz")
                ?? bundle.url(forResource: "TallBox", withExtension: "usdz", subdirectory: "Fixtures"))
        }

        private func bounds(of id: ObjectID, in app: AppModel) throws -> BoundingBox {
            let object = try #require(app.workspace.object(withID: id))
            return try #require(WorkspaceScene.geometryBounds(of: object))
        }

        private func modelFiles(in project: ProjectStore.Info) -> [String] {
            let folder = storage.appending(path: "Projects/\(project.id.uuidString)/models")
            return (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        }

        private func reopen(_ project: ProjectStore.Info) async throws -> AppModel {
            let app = AppModel()
            #expect(await app.openProject(try #require(app.projects.first { $0.id == project.id })))
            return app
        }

        @Test func anImportedModelIsFittedLikeTheBuiltInObjects() async throws {
            let app = try await makeApp()
            await app.importModel(from: try tallBox())

            #expect(app.objectError == nil)
            let summary = try #require(app.selectedObject)
            #expect(summary.name == "TallBox")
            #expect(summary.source == .imported)
            #expect(summary.recipe.importedFileID != nil)
            #expect(!summary.recipe.canRecolor)

            // Its longest side (the height) is fitted, it's centered, and it rests on the base.
            let box = try bounds(of: summary.id, in: app)
            #expect(abs(box.extents.y - ImportedModels.fittedSize) < 0.001)
            #expect(abs(box.extents.x - ImportedModels.fittedSize / 4) < 0.001)
            #expect(abs(box.min.y) < 0.001)
            #expect(abs(box.center.x) < 0.001 && abs(box.center.z) < 0.001)
        }

        @Test func importedModelsComeBackWithUndoAndReopening() async throws {
            let app = try await makeApp()
            await app.importModel(from: try tallBox())
            let id = try #require(app.selectedObjectID)
            let project = try #require(app.currentProject)
            #expect(modelFiles(in: project).count == 1)

            app.deleteSelectedObject()
            #expect(app.objects.isEmpty)
            app.undo()
            #expect(abs(try bounds(of: id, in: app).extents.y - ImportedModels.fittedSize) < 0.001)
            #expect(app.saveNow())

            // A fresh launch loads the model from the project folder.
            ImportedModels.keepOnly([])
            let reopened = try await reopen(project)
            #expect(reopened.objects.map(\.id) == [id])
            #expect(abs(try bounds(of: id, in: reopened).extents.y - ImportedModels.fittedSize) < 0.001)
            #expect(reopened.projectNotice == nil)
        }

        @Test func aFileThatIsntAModelIsRefused() async throws {
            let app = try await makeApp()
            let project = try #require(app.currentProject)
            let fake = storage.appending(path: "Not a model.usdz")
            try Data("hello".utf8).write(to: fake)

            await app.importModel(from: fake)
            #expect(app.objectError?.contains("Not a model.usdz") == true)
            #expect(app.objects.isEmpty)
            #expect(modelFiles(in: project).isEmpty)
            #expect(!app.isImportingModel)
        }

        @Test func aMissingModelFileLeavesAGrayBoxAndKeepsTheObject() async throws {
            let app = try await makeApp()
            await app.importModel(from: try tallBox())
            let summary = try #require(app.selectedObject)
            let fileID = try #require(summary.recipe.importedFileID)
            let project = try #require(app.currentProject)
            #expect(app.saveNow())

            let file = ProjectStore.modelFile(project.id, fileID)
            let aside = storage.appending(path: "aside.usdz")
            try FileManager.default.moveItem(at: file, to: aside)
            ImportedModels.keepOnly([])

            let reopened = try await reopen(project)
            #expect(reopened.objects.map(\.recipe) == [summary.recipe])
            #expect(reopened.projectNotice?.contains("imported model") == true)
            // The stand-in is the 4 cm placeholder box.
            #expect(abs(try bounds(of: summary.id, in: reopened).extents.y - 0.04) < 0.001)

            // Saving keeps the object pointing at its file, so it comes back with the file.
            reopened.addKeyframe()
            #expect(reopened.saveNow())
            try FileManager.default.moveItem(at: aside, to: file)
            ImportedModels.keepOnly([])
            let restored = try await reopen(project)
            #expect(abs(try bounds(of: summary.id, in: restored).extents.y - ImportedModels.fittedSize) < 0.001)
            #expect(restored.projectNotice == nil)
        }

        @Test func unusedModelFilesAreRemovedWhenTheProjectOpens() async throws {
            let app = try await makeApp()
            await app.importModel(from: try tallBox())
            let project = try #require(app.currentProject)
            app.deleteSelectedObject()
            #expect(app.saveNow())
            // Kept while the project is open, since undo could bring the object back.
            #expect(modelFiles(in: project).count == 1)

            _ = try await reopen(project)
            #expect(modelFiles(in: project).isEmpty)
        }

        @Test func duplicatingAProjectCopiesItsModels() async throws {
            let app = try await makeApp()
            await app.importModel(from: try tallBox())
            let id = try #require(app.selectedObjectID)
            let project = try #require(app.currentProject)
            #expect(app.saveNow())

            app.duplicateProject(project.id)
            let copy = try #require(app.projects.first { $0.id != project.id })
            #expect(modelFiles(in: copy).count == 1)
            ImportedModels.keepOnly([])
            let reopened = try await reopen(copy)
            #expect(abs(try bounds(of: id, in: reopened).extents.y - ImportedModels.fittedSize) < 0.001)
        }

        @Test(arguments: [
            ("old_red-barn.usdz", "old red barn"),
            ("Chair.usdz", "Chair"),
            ("__.usdz", "Model"),
        ])
        func modelNamesComeFromTheFileName(file: String, name: String) {
            #expect(AppModel.modelName(for: URL(filePath: "/tmp/\(file)")) == name)
        }
    }
}
