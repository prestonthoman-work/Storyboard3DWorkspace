//
//  WorkflowGuide.swift
//  Storyboard3DWorkspace
//

import Foundation

/// The path from an empty table to a finished storyboard. The current step is worked out
/// from the project itself, so the guide always points at what to do next.
enum WorkflowStep: Int, CaseIterable, Comparable {
    case addObjects
    case firstKeyframe
    case secondKeyframe
    case takePhotos
    case share

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// The steps that count toward progress; `share` means everything is done.
    static let milestones: [WorkflowStep] = [.addObjects, .firstKeyframe, .secondKeyframe, .takePhotos]

    var title: String {
        switch self {
        case .addObjects: "Build your set"
        case .firstKeyframe: "Save your first shot"
        case .secondKeyframe: "Add a second keyframe"
        case .takePhotos: "Photograph each shot"
        case .share: "Your storyboard is ready"
        }
    }

    var detail: String {
        switch self {
        case .addObjects:
            "Tap a library card to place an object, then pinch and drag it into place."
        case .firstKeyframe:
            "A keyframe saves where everything is. Arrange the scene, then add one."
        case .secondKeyframe:
            "Move something, then add another keyframe. Playback glides between them."
        case .takePhotos:
            "Look at the scene through the frame and take a photo for each keyframe."
        case .share:
            "Screen it full size, or export a video or a printable sheet."
        }
    }

    var symbol: String {
        switch self {
        case .addObjects: "cube"
        case .firstKeyframe: "diamond"
        case .secondKeyframe: "point.forward.to.point.capsulepath"
        case .takePhotos: "camera"
        case .share: "sparkles"
        }
    }

    /// Where this step is done.
    var tab: WorkspaceTab {
        switch self {
        case .addObjects: .objects
        case .firstKeyframe, .secondKeyframe, .takePhotos, .share: .animate
        }
    }
}

extension AppModel {
    var workflowStep: WorkflowStep {
        let keyframes = animator.timeline.keyframes
        if objects.isEmpty { return .addObjects }
        if keyframes.isEmpty { return .firstKeyframe }
        if keyframes.count < 2 { return .secondKeyframe }
        let coverage = slideshowCoverage
        if coverage.withPhoto < coverage.total { return .takePhotos }
        return .share
    }

    /// The first keyframe that still needs a photo.
    var firstKeyframeWithoutPhoto: Keyframe? {
        animator.timeline.keyframes.first { photos.primaryPhoto(for: $0.id) == nil }
    }
}
