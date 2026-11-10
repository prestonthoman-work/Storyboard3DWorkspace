//
//  StarterScene.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// A ready-made set to start a project from, so the first minute is spent framing shots
/// instead of placing every object by hand.
enum StarterScene: String, CaseIterable, Identifiable {
    case blank
    case streetCorner
    case backyard

    var id: String { rawValue }

    struct Placement {
        let kind: SampleObjectCatalog.Kind
        /// Position on the base, in meters from its center (x right, z toward the viewer).
        let x: Float
        let z: Float
        var yawDegrees: Float = 0
        var color: String? = nil
        var name: String? = nil
        /// Where it is in the second keyframe, if it moves.
        var movesTo: SIMD2<Float>? = nil
    }

    var name: String {
        switch self {
        case .blank: "Blank"
        case .streetCorner: "Street Corner"
        case .backyard: "Backyard"
        }
    }

    var subtitle: String {
        switch self {
        case .blank: "An empty base, ready for anything"
        case .streetCorner: "City block with a car already in motion"
        case .backyard: "A house, a fence, and a garden"
        }
    }

    var symbol: String {
        switch self {
        case .blank: "circle.dashed"
        case .streetCorner: "car.side"
        case .backyard: "house"
        }
    }

    var template: BaseTemplate {
        switch self {
        case .blank, .backyard: .grass
        case .streetCorner: .streets
        }
    }

    var placements: [Placement] {
        switch self {
        case .blank:
            []
        case .streetCorner:
            [
                Placement(kind: .building, x: -0.13, z: -0.13),
                Placement(kind: .building, x: 0.04, z: -0.16, yawDegrees: 8, color: "blue"),
                Placement(kind: .house, x: 0.17, z: -0.09, yawDegrees: -20),
                Placement(kind: .lamp, x: -0.09, z: 0.06),
                Placement(kind: .lamp, x: 0.11, z: 0.06),
                Placement(kind: .tree, x: -0.19, z: 0.05),
                Placement(kind: .tree, x: 0.2, z: 0.07),
                Placement(kind: .shrub, x: 0.0, z: 0.16),
                Placement(kind: .car, x: -0.17, z: -0.02, name: "Hero Car", movesTo: [0.15, -0.02]),
            ]
        case .backyard:
            [
                Placement(kind: .house, x: 0, z: -0.12),
                Placement(kind: .fence, x: -0.12, z: 0.17),
                Placement(kind: .fence, x: 0.0, z: 0.19),
                Placement(kind: .fence, x: 0.12, z: 0.17),
                Placement(kind: .tree, x: -0.18, z: -0.04),
                Placement(kind: .tree, x: 0.18, z: -0.02, color: "orange"),
                Placement(kind: .shrub, x: -0.08, z: 0.03),
                Placement(kind: .shrub, x: 0.09, z: 0.05),
                Placement(kind: .rock, x: 0.03, z: 0.1),
            ]
        }
    }

    /// Starters with motion get two keyframes so playback works right away.
    var isAnimated: Bool { placements.contains { $0.movesTo != nil } }
}
