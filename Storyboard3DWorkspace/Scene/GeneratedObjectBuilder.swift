//
//  GeneratedObjectBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// One simple shape of a generated object. A generated object is saved as its list of
/// parts, so it rebuilds exactly the same way after undo or reopening the project.
struct GeneratedPart: Codable, Equatable {
    enum Shape: String, Codable, CaseIterable {
        case box, roundedBox, sphere, cylinder, cone
        /// A triangular prism like a gable roof: ridge along x at the top, before any yaw.
        case wedge
    }

    /// Which way a round shape's axis points. Cones point their tip along it.
    enum Orientation: String, Codable, CaseIterable {
        /// Axis straight up (a cone's tip points up).
        case upright
        /// Axis straight down (a cone's tip points down, like a funnel or lamp shade).
        case upsideDown
        /// Axis left to right, like an axle across a cart.
        case alongX
        /// Axis front to back, like a car's wheel axle or a tunnel.
        case alongZ
    }

    var shape: Shape
    /// The center of the part's bounding box, in meters.
    var center: SIMD3<Float>
    /// The part's full size along x, y and z after it's turned, in meters.
    var size: SIMD3<Float>
    var orientation: Orientation
    /// A name from `GeneratedPalette`.
    var color: String
    /// Main-body parts take the object's color when it's recolored.
    var isMainBody: Bool
    /// A turn about the vertical axis, in radians, counterclockwise seen from above. `size`
    /// is measured before the turn.
    var yaw: Float? = nil

    /// Half the part's extent along x and z once it's turned.
    var turnedHalfExtent: SIMD3<Float> {
        guard let yaw, yaw != 0 else { return size / 2 }
        let c = abs(cos(yaw)), s = abs(sin(yaw))
        return SIMD3(c * size.x + s * size.z, size.y, s * size.x + c * size.z) / 2
    }
}

/// The colors and finishes generated parts are painted with, by name.
enum GeneratedPalette {
    static let names: [String] = [
        "red", "orange", "yellow", "green", "darkGreen", "teal", "blue", "navy", "purple", "pink",
        "brown", "darkBrown", "tan", "cream", "white", "lightGray", "gray", "darkGray", "black",
        "silver", "gold", "glass", "light"
    ]

    static func look(_ name: String) -> (color: UIColor, finish: LowPoly.Finish) {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        switch name {
        case "red": return (rgb(0.80, 0.30, 0.27), .satin)
        case "orange": return (rgb(0.92, 0.56, 0.25), .satin)
        case "yellow": return (rgb(0.95, 0.82, 0.35), .satin)
        case "green": return (rgb(0.40, 0.64, 0.38), .matte)
        case "darkGreen": return (rgb(0.24, 0.44, 0.27), .matte)
        case "teal": return (rgb(0.30, 0.62, 0.62), .satin)
        case "blue": return (rgb(0.35, 0.52, 0.80), .satin)
        case "navy": return (rgb(0.18, 0.25, 0.45), .satin)
        case "purple": return (rgb(0.58, 0.44, 0.75), .satin)
        case "pink": return (rgb(0.92, 0.62, 0.70), .satin)
        case "brown": return (rgb(0.52, 0.38, 0.27), .satin)
        case "darkBrown": return (rgb(0.34, 0.23, 0.16), .satin)
        case "tan": return (rgb(0.80, 0.68, 0.50), .matte)
        case "cream": return (rgb(0.95, 0.91, 0.82), .matte)
        case "white": return (rgb(0.95, 0.94, 0.91), .satin)
        case "lightGray": return (rgb(0.75, 0.75, 0.76), .matte)
        case "darkGray": return (rgb(0.36, 0.36, 0.38), .matte)
        case "black": return (rgb(0.16, 0.16, 0.18), .satin)
        case "silver": return (rgb(0.78, 0.79, 0.81), .metal)
        case "gold": return (rgb(0.85, 0.68, 0.32), .metal)
        case "glass": return (rgb(0.40, 0.52, 0.64), .glass)
        case "light": return (rgb(1, 0.86, 0.58), .glow)
        default: return (rgb(0.55, 0.56, 0.58), .matte)
        }
    }
}

/// Builds generated objects from their parts, and fits freshly generated parts to the set.
enum GeneratedObjectBuilder {
    /// Generated objects are designed at real-world size and shrunk to the characters'
    /// scale, so a chair is the right height for a character to sit on.
    static let scale: Float = RigLayout.miniatureScale
    /// Longest side limits after scaling, in meters, so nothing fills the room or vanishes.
    static let sizeLimits: ClosedRange<Float> = 0.004...0.25
    static let maximumParts = 24

    /// Converts parts sized in real-world centimeters to the miniature: scaled, centered on
    /// the origin, and resting on y = 0. Parts with unusable sizes are dropped.
    static func fit(_ parts: [GeneratedPart]) -> [GeneratedPart] {
        var parts = parts.prefix(maximumParts).compactMap { part -> GeneratedPart? in
            guard all(part.center, \.isFinite), all(part.size, \.isFinite), all(part.size, { $0 > 0 }) else { return nil }
            var part = part
            part.size = simd_max(part.size, SIMD3(repeating: 0.1)) * 0.01 * scale
            part.center *= 0.01 * scale
            if !GeneratedPalette.names.contains(part.color) { part.color = "gray" }
            return part
        }
        guard !parts.isEmpty else { return [] }

        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = -low
        for part in parts {
            low = simd_min(low, part.center - part.turnedHalfExtent)
            high = simd_max(high, part.center + part.turnedHalfExtent)
        }
        let shift = SIMD3((low.x + high.x) / 2, low.y, (low.z + high.z) / 2)
        let longest = max(high.x - low.x, high.y - low.y, high.z - low.z)
        let factor = min(max(longest, sizeLimits.lowerBound), sizeLimits.upperBound) / longest
        for index in parts.indices {
            parts[index].center = (parts[index].center - shift) * factor
            parts[index].size *= factor
        }
        return parts
    }

    /// Builds the object, painting main-body parts with `tint` when there is one.
    static func make(name: String, parts: [GeneratedPart], tint: UIColor?) -> Entity {
        let object = Entity()
        object.name = name
        for part in parts {
            var (color, finish) = GeneratedPalette.look(part.color)
            if part.isMainBody, let tint {
                color = tint
                if finish == .glass || finish == .glow { finish = .satin }
            }
            let entity = makePart(part, material: LowPoly.material(color, finish))
            entity.components.set(GroundingShadowComponent(castsShadow: true))
            object.addChild(entity)
        }
        return object
    }

    private static func makePart(_ part: GeneratedPart, material: PhysicallyBasedMaterial) -> ModelEntity {
        // The shape's own size before it's turned, and the turn that lays its axis down.
        let size = part.size
        let (local, rotation): (SIMD3<Float>, simd_quatf) = switch part.orientation {
        case .upright: (size, simd_quatf(angle: 0, axis: [0, 1, 0]))
        case .upsideDown: (size, simd_quatf(angle: .pi, axis: [1, 0, 0]))
        case .alongX: (SIMD3(size.y, size.x, size.z), simd_quatf(angle: -.pi / 2, axis: [0, 0, 1]))
        case .alongZ: (SIMD3(size.x, size.z, size.y), simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        }

        let entity: ModelEntity
        var position = part.center
        switch part.shape {
        case .box:
            entity = ModelEntity(mesh: .generateBox(size: local), materials: [material])
        case .roundedBox:
            entity = ModelEntity(mesh: .generateBox(size: local, cornerRadius: local.min() * 0.2), materials: [material])
        case .sphere:
            entity = ModelEntity(mesh: unitSphere, materials: [material])
            entity.scale = local
        case .cylinder:
            entity = ModelEntity(mesh: unitCylinder, materials: [material])
            entity.scale = local
        case .cone:
            entity = ModelEntity(mesh: unitCone, materials: [material])
            entity.scale = local
        case .wedge:
            // Built resting on y = 0 at full size, ridge along x; orientation doesn't apply.
            let mesh = LowPoly.gableRoof(width: size.x, depth: size.z, height: size.y)
                ?? .generateBox(size: size)
            entity = ModelEntity(mesh: mesh, materials: [material])
            position.y -= size.y / 2
            let yaw = simd_quatf(angle: part.yaw ?? 0, axis: [0, 1, 0])
            entity.position = position
            entity.orientation = yaw
            return entity
        }
        entity.position = position
        entity.orientation = simd_quatf(angle: part.yaw ?? 0, axis: [0, 1, 0]) * rotation
        return entity
    }

    // Unit shapes (1 m across), scaled per part, so repeated shapes share one mesh.
    private static let unitSphere = MeshResource.generateSphere(radius: 0.5)
    private static let unitCylinder = MeshResource.generateCylinder(height: 1, radius: 0.5)
    private static let unitCone = MeshResource.generateCone(height: 1, radius: 0.5)

    private static func all(_ vector: SIMD3<Float>, _ test: (Float) -> Bool) -> Bool {
        test(vector.x) && test(vector.y) && test(vector.z)
    }
}
