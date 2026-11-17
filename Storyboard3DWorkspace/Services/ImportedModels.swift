//
//  ImportedModels.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit
import UniformTypeIdentifiers

/// 3D models imported from USDZ files.
///
/// Loading a file is slow and asynchronous, but rebuilding objects (undo, redo, reopening a
/// project) happens synchronously through `ModelRecipe.makeEntity()`. So each file is loaded
/// once, when it's imported or its project opens, and kept here as a prototype. Objects are
/// copies of it.
enum ImportedModels {
    /// The file types that can be imported. USDZ packages carry their textures inside, so one
    /// file is the whole model.
    static let contentTypes: [UTType] = [.usdz]

    /// The size an imported model is fitted to when it's placed: its longest side, in meters,
    /// about the size of the built-in objects. It can be resized afterwards like any object.
    static let fittedSize: Float = 0.1

    enum ImportError: LocalizedError {
        case nothingVisible

        var errorDescription: String? {
            switch self {
            case .nothingVisible: "The file has no visible geometry."
            }
        }
    }

    private static var prototypes: [UUID: Entity] = [:]

    /// Loads a model file and keeps it for making copies. Throws if the file isn't a model
    /// RealityKit can read, or has nothing visible in it.
    static func load(_ fileID: UUID, from url: URL) async throws {
        let model = try await Entity(contentsOf: url)
        prototypes[fileID] = try fitted(model)
    }

    static func isLoaded(_ fileID: UUID) -> Bool {
        prototypes[fileID] != nil
    }

    /// A copy of a loaded model, ready to place; nil if it isn't loaded.
    static func instance(of fileID: UUID) -> Entity? {
        prototypes[fileID]?.clone(recursive: true)
    }

    /// Lets go of every loaded model except these, such as when another project opens.
    static func keepOnly(_ fileIDs: Set<UUID>) {
        prototypes = prototypes.filter { fileIDs.contains($0.key) }
    }

    /// Wraps a model so it's built like the built-in objects: centered on the origin, resting
    /// on y = 0, its longest side `fittedSize`, casting a shadow on the base.
    static func fitted(_ model: Entity) throws -> Entity {
        let bounds = model.visualBounds(relativeTo: nil)
        let longest = bounds.extents.max()
        guard !bounds.isEmpty, longest.isFinite, longest > 0 else { throw ImportError.nothingVisible }

        prepare(model)
        model.position -= SIMD3(bounds.center.x, bounds.min.y, bounds.center.z)
        let container = Entity()
        container.name = "Imported Model"
        container.addChild(model)
        container.scale = SIMD3(repeating: fittedSize / longest)
        return container
    }

    /// Strips what would fight the workspace (anchors that pin parts to the room, physics
    /// that would drop them on their own) and adds shadows to everything visible.
    private static func prepare(_ entity: Entity) {
        entity.components.remove(AnchoringComponent.self)
        entity.components.remove(PhysicsBodyComponent.self)
        entity.components.remove(PhysicsMotionComponent.self)
        if entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children {
            prepare(child)
        }
    }
}
