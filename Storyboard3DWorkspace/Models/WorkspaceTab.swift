//
//  WorkspaceTab.swift
//  Storyboard3DWorkspace
//

import Foundation

/// The workflow steps shown as tabs in the control panel, in the order you'd use them.
enum WorkspaceTab: Int, Hashable, CaseIterable, Identifiable {
    /// The base and the backdrop behind it.
    case base
    case objects
    /// Keyframes, and each keyframe's photos.
    case animate
    /// Free shooting and the photo library.
    case photos

    var id: Self { self }

    /// 1-based position in the workflow.
    var number: Int { rawValue + 1 }

    var title: String {
        switch self {
        case .base: "Base"
        case .objects: "Objects"
        case .animate: "Animate"
        case .photos: "Camera"
        }
    }

    var symbol: String {
        switch self {
        case .base: "circle.circle"
        case .objects: "cube"
        case .animate: "film"
        case .photos: "camera"
        }
    }

    /// One line on what this step is for, shown under the step strip.
    var purpose: String {
        switch self {
        case .base: "Put the base on your table, then pick its surface, size, and backdrop."
        case .objects: "Add objects and characters, then pinch and drag them into place."
        case .animate: "Save each shot, then frame it and take its photo."
        case .photos: "Take photos, and open the library of every photo in the project."
        }
    }
}
