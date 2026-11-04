//
//  ProjectState.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit

/// A complete, value-type snapshot of the project's editable content: the base, every
/// object and its pose, the keyframes, and the photo library's attachments.
///
/// Undo keeps a stack of these, and saving writes one to disk. Image data isn't stored
/// here: photos are referenced by ID, and their pixels live in `PhotoLibrary` and on disk.
struct ProjectState: Codable, Equatable {
    struct Base: Codable, Equatable {
        var name: String
        var recipe: ModelRecipe
        /// Nil for a template; otherwise who generated it.
        var generatedBy: ModelSource?
        var diameterCentimeters: Double
    }

    struct Object: Codable, Equatable {
        var id: ObjectID
        var name: String
        var source: ModelSource
        var recipe: ModelRecipe
        var transform: CodableTransform
        var isVisible: Bool
    }

    struct KeyframeState: Codable, Equatable {
        var id: Keyframe.ID
        var time: TimeInterval
        var poses: [ObjectID: CodableTransform]
        /// Optional so projects saved before notes existed still load.
        var note: String?
    }

    struct Photo: Codable, Equatable {
        var id: CapturedPhoto.ID
        var takenAt: Date
        var lens: CaptureLens
        var assignment: CapturedPhoto.Assignment
    }

    var base: Base
    var objects: [Object]
    var keyframes: [KeyframeState]
    var selectedKeyframeID: Keyframe.ID?
    var photos: [Photo]
    var primaryPhotoIDs: [Keyframe.ID: CapturedPhoto.ID]

    /// A new project: the Grass base at the default size, and nothing else.
    static let empty = ProjectState(
        base: Base(name: BaseTemplate.grass.name, recipe: .baseTemplate(BaseTemplate.grass.rawValue),
                   generatedBy: nil, diameterCentimeters: BaseSizeLimits.defaultWidth),
        objects: [], keyframes: [], selectedKeyframeID: nil, photos: [], primaryPhotoIDs: [:]
    )
}

/// `Transform` in a form that can be saved.
struct CodableTransform: Codable, Equatable {
    var translation: SIMD3<Float>
    /// Quaternion as (x, y, z, w).
    var rotation: SIMD4<Float>
    var scale: SIMD3<Float>

    init(_ transform: Transform) {
        translation = transform.translation
        rotation = transform.rotation.vector
        scale = transform.scale
    }

    var transform: Transform {
        Transform(scale: scale, rotation: simd_quatf(vector: rotation), translation: translation)
    }
}

extension Keyframe {
    init(_ state: ProjectState.KeyframeState) {
        self.init(id: state.id, time: state.time, poses: state.poses.mapValues(\.transform), note: state.note ?? "")
    }
}

extension ProjectState.KeyframeState {
    init(_ keyframe: Keyframe) {
        self.init(id: keyframe.id, time: keyframe.time, poses: keyframe.poses.mapValues { CodableTransform($0) },
                  note: keyframe.note.isEmpty ? nil : keyframe.note)
    }
}
