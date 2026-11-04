//
//  LightingPreset.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// Lighting moods for captures. They change only the rendered photo: the scene in the
/// headset is lit by the real room.
enum LightingPreset: String, Codable, CaseIterable, Identifiable {
    case studio
    case goldenHour
    case overcast
    case night

    var id: String { rawValue }

    var name: String {
        switch self {
        case .studio: "Studio"
        case .goldenHour: "Golden Hour"
        case .overcast: "Overcast"
        case .night: "Night"
        }
    }

    var symbol: String {
        switch self {
        case .studio: "lightbulb"
        case .goldenHour: "sun.horizon"
        case .overcast: "cloud"
        case .night: "moon.stars"
        }
    }

    /// A directional light placed relative to the camera: `front` toward the camera,
    /// `side` to the camera's right (negative is left), and `up`.
    struct Light {
        var color: SIMD3<Float>
        var intensity: Float
        var front: Float
        var side: Float
        var up: Float
    }

    var key: Light {
        switch self {
        case .studio: Light(color: [1, 1, 1], intensity: 2600, front: 0.8, side: -0.9, up: 1.6)
        case .goldenHour: Light(color: [1, 0.8, 0.58], intensity: 2700, front: 0.4, side: -1.4, up: 0.45)
        case .overcast: Light(color: [0.9, 0.92, 0.96], intensity: 700, front: 0.3, side: -0.2, up: 2.5)
        case .night: Light(color: [0.62, 0.72, 1], intensity: 650, front: 0.2, side: 1.0, up: 1.2)
        }
    }

    var fill: Light {
        switch self {
        case .studio: Light(color: [1, 1, 1], intensity: 800, front: 1.0, side: 1.0, up: 0.4)
        case .goldenHour: Light(color: [0.55, 0.66, 1], intensity: 450, front: 1.0, side: 1.0, up: 0.5)
        case .overcast: Light(color: [0.9, 0.92, 0.96], intensity: 600, front: 1.0, side: 1.0, up: 0.8)
        case .night: Light(color: [0.4, 0.45, 0.7], intensity: 140, front: 1.0, side: -1.0, up: 0.3)
        }
    }

    /// Placed behind the scene to outline it against the backdrop.
    var rim: Light {
        switch self {
        case .studio: Light(color: [1, 1, 1], intensity: 1400, front: -1.0, side: 0, up: 1.2)
        case .goldenHour: Light(color: [1, 0.78, 0.5], intensity: 2000, front: -1.0, side: 0.6, up: 0.6)
        case .overcast: Light(color: [0.9, 0.92, 0.96], intensity: 250, front: -1.0, side: 0, up: 1.5)
        case .night: Light(color: [0.55, 0.65, 1], intensity: 1000, front: -1.0, side: -0.4, up: 1.0)
        }
    }

    var keyCastsShadows: Bool { self != .overcast }

    /// Sky-to-ground gradient used as ambient (image-based) light.
    var environment: (top: SIMD3<Float>, middle: SIMD3<Float>, bottom: SIMD3<Float>) {
        switch self {
        case .studio: ([0.96, 0.97, 1], [0.80, 0.82, 0.85], [0.42, 0.42, 0.43])
        case .goldenHour: ([1, 0.86, 0.72], [0.86, 0.72, 0.6], [0.38, 0.3, 0.27])
        case .overcast: ([0.82, 0.84, 0.87], [0.72, 0.74, 0.77], [0.5, 0.51, 0.53])
        case .night: ([0.18, 0.22, 0.38], [0.1, 0.12, 0.2], [0.04, 0.04, 0.06])
        }
    }

    /// Exponent applied to the ambient light: higher is brighter.
    var environmentExposure: Float {
        switch self {
        case .studio: 0.4
        case .goldenHour: 0.2
        case .overcast: 0.9
        case .night: -0.6
        }
    }

    /// Multiplies the backdrop image so it matches the mood.
    var backdropTint: SIMD3<Float> {
        switch self {
        case .studio: [1, 1, 1]
        case .goldenHour: [1, 0.88, 0.74]
        case .overcast: [0.74, 0.77, 0.82]
        case .night: [0.32, 0.37, 0.55]
        }
    }
}
