//
//  PlacedObject.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit

/// A placed object's permanent identity. RealityKit's own entity IDs change every launch,
/// so keyframes, undo, and saved projects refer to objects by this instead.
typealias ObjectID = UUID

struct PlacedObjectComponent: Component {
    var id: ObjectID
}
