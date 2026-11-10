//
//  WorkspaceTab.swift
//  Storyboard3DWorkspace
//

import Foundation

/// The workflow steps shown as tabs in the control panel, in the order you'd use them.
enum WorkspaceTab: Hashable {
    /// The base and the backdrop behind it.
    case set
    case objects
    /// Keyframes, and each keyframe's photos.
    case animate
    /// Free shooting and the photo library.
    case photos
}
