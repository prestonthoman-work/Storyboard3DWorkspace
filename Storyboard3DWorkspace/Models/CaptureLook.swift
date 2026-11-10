//
//  CaptureLook.swift
//  Storyboard3DWorkspace
//

import Foundation

/// Film aspect ratios. Captures always render at 16:9 so every export stays the same
/// size; narrower formats are letterboxed with black bars, as on a storyboard frame.
nonisolated enum FrameFormat: String, Codable, CaseIterable, Identifiable {
    case widescreen
    case flat
    case scope

    var id: String { rawValue }

    var aspect: Float {
        switch self {
        case .widescreen: CaptureLens.aspect
        case .flat: 1.85
        case .scope: 2.39
        }
    }

    var label: String {
        switch self {
        case .widescreen: "16:9"
        case .flat: "1.85:1"
        case .scope: "2.39:1"
        }
    }

    var name: String {
        switch self {
        case .widescreen: "Widescreen"
        case .flat: "Flat"
        case .scope: "Scope"
        }
    }

    /// The fraction of the 16:9 frame's height covered by each letterbox bar.
    var matteFraction: Float {
        max(0, (1 - CaptureLens.aspect / aspect) / 2)
    }
}

/// How a capture is finished after rendering: its frame format, and whether it gets a
/// film grade (tone curve, gentle bloom, vignette, and grain).
nonisolated struct CaptureLook: Codable, Equatable {
    var format: FrameFormat = .widescreen
    var isFilmGraded = true

    /// New projects start with the film grade on.
    static let standard = CaptureLook()
    /// The plain render, for photos taken before looks existed.
    static let plain = CaptureLook(format: .widescreen, isFilmGraded: false)
}
