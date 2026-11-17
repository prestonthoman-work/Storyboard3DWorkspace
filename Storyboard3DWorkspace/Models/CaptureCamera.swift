//
//  CaptureCamera.swift
//  Storyboard3DWorkspace
//

import Foundation
import simd

/// A capture lens, named by its full-frame focal length like a Blender camera. Any focal
/// length in `range` can be used; `presets` are the common primes.
///
/// Saved as a bare number of millimeters, so projects from when only four lenses existed
/// (saved as 24, 35, 50, or 85) still read.
nonisolated struct CaptureLens: Codable, Hashable, Identifiable {
    /// Full-frame focal length in millimeters.
    let focalLength: Int

    static let range: ClosedRange<Int> = 12...200

    init(_ focalLength: Int) {
        self.focalLength = min(max(focalLength, Self.range.lowerBound), Self.range.upperBound)
    }

    static let wide = CaptureLens(24)
    static let standard = CaptureLens(35)
    static let normal = CaptureLens(50)
    static let portrait = CaptureLens(85)
    /// Common primes, from ultra-wide to telephoto.
    static let presets: [CaptureLens] = [CaptureLens(18), .wide, .standard, .normal, .portrait, CaptureLens(135)]

    var id: Int { focalLength }
    var label: String { "\(focalLength) mm" }

    init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(focalLength)
    }

    /// Output frame aspect ratio (16:9).
    static let aspect: Float = 16 / 9

    /// Vertical field of view in radians, for a 36 mm-wide sensor cropped to 16:9.
    var verticalFOV: Float {
        let sensorHeight: Float = 36 / Self.aspect
        return 2 * atan(sensorHeight / 2 / Float(focalLength))
    }

    var horizontalFOV: Float {
        2 * atan(tan(verticalFOV / 2) * Self.aspect)
    }
}

/// Where the capture camera is and which way it looks. Saved with each photo so it
/// can be retaken or re-rendered from the same angle.
struct CaptureCamera: Codable, Equatable {
    var position: SIMD3<Float>
    /// Camera looks down local -Z with +Y up.
    var orientation: simd_quatf
    var lens: CaptureLens

    init(position: SIMD3<Float>, orientation: simd_quatf, lens: CaptureLens) {
        self.position = position
        self.orientation = orientation
        self.lens = lens
    }

    private enum CodingKeys: String, CodingKey { case position, rotation, lens }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        position = try container.decode(SIMD3<Float>.self, forKey: .position)
        orientation = simd_quatf(vector: try container.decode(SIMD4<Float>.self, forKey: .rotation))
        lens = try container.decode(CaptureLens.self, forKey: .lens)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(position, forKey: .position)
        try container.encode(orientation.vector, forKey: .rotation)
        try container.encode(lens, forKey: .lens)
    }

    /// A camera at the viewer's head, facing where they face, with the roll removed so
    /// the horizon stays level, like a camera on a tripod.
    static func level(fromHead head: simd_float4x4, lens: CaptureLens) -> CaptureCamera {
        let position = SIMD3(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let forward = -SIMD3(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        return CaptureCamera(position: position, orientation: .upright(facing: -forward), lens: lens)
    }

    /// Used when head tracking isn't available (such as in Simulator): stand at `position`
    /// and look straight at `target`.
    static func looking(from position: SIMD3<Float>, at target: SIMD3<Float>, lens: CaptureLens) -> CaptureCamera {
        CaptureCamera(position: position, orientation: .upright(facing: position - target), lens: lens)
    }
}
