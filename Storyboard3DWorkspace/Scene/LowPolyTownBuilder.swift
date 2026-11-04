//
//  LowPolyTownBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Builds a small low-poly town from boxes, cones, and cylinders.
///
/// The town is about 56 cm square, centered on the origin, with its base resting on y = 0.
enum LowPolyTownBuilder {
    private enum Palette {
        static let grass = UIColor(red: 0.60, green: 0.75, blue: 0.50, alpha: 1)
        static let road = UIColor(red: 0.36, green: 0.37, blue: 0.40, alpha: 1)
        static let laneMark = UIColor(red: 0.96, green: 0.90, blue: 0.62, alpha: 1)
        static let cream = UIColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1)
        static let terracotta = UIColor(red: 0.84, green: 0.50, blue: 0.38, alpha: 1)
        static let sage = UIColor(red: 0.66, green: 0.74, blue: 0.64, alpha: 1)
        static let slate = UIColor(red: 0.55, green: 0.63, blue: 0.74, alpha: 1)
        static let sky = UIColor(red: 0.62, green: 0.78, blue: 0.88, alpha: 1)
        static let roofDark = UIColor(red: 0.42, green: 0.40, blue: 0.42, alpha: 1)
        static let roofRed = UIColor(red: 0.70, green: 0.32, blue: 0.27, alpha: 1)
        static let trunk = UIColor(red: 0.47, green: 0.34, blue: 0.24, alpha: 1)
        static let foliage = UIColor(red: 0.33, green: 0.58, blue: 0.36, alpha: 1)
    }

    private enum Roof {
        case flat
        case cone
    }

    private struct Building {
        let x: Float
        let z: Float
        let width: Float
        let depth: Float
        let height: Float
        let color: UIColor
        let roof: Roof
    }

    private static let baseSize: Float = 0.56
    private static let baseHeight: Float = 0.024
    private static let roadWidth: Float = 0.07

    private static let buildings: [Building] = [
        // Back right
        Building(x: 0.12, z: -0.13, width: 0.07, depth: 0.07, height: 0.20, color: Palette.slate, roof: .flat),
        Building(x: 0.22, z: -0.07, width: 0.06, depth: 0.05, height: 0.06, color: Palette.cream, roof: .cone),
        Building(x: 0.22, z: -0.21, width: 0.05, depth: 0.05, height: 0.08, color: Palette.terracotta, roof: .flat),
        // Back left
        Building(x: -0.14, z: -0.10, width: 0.11, depth: 0.06, height: 0.10, color: Palette.cream, roof: .flat),
        Building(x: -0.08, z: -0.22, width: 0.05, depth: 0.06, height: 0.05, color: Palette.terracotta, roof: .cone),
        Building(x: -0.21, z: -0.21, width: 0.06, depth: 0.06, height: 0.14, color: Palette.sage, roof: .flat),
        // Front right
        Building(x: 0.10, z: 0.10, width: 0.06, depth: 0.06, height: 0.08, color: Palette.sky, roof: .flat),
        Building(x: 0.21, z: 0.10, width: 0.06, depth: 0.05, height: 0.12, color: Palette.cream, roof: .flat),
        Building(x: 0.12, z: 0.22, width: 0.08, depth: 0.05, height: 0.05, color: Palette.terracotta, roof: .cone)
    ]

    /// Front left is a small park; the rest are street trees.
    private static let treePositions: [SIMD2<Float>] = [
        [-0.10, 0.10], [-0.19, 0.08], [-0.14, 0.18], [-0.23, 0.16], [-0.07, 0.22],
        [0.23, 0.22], [0.06, -0.23], [-0.24, -0.06]
    ]

    static func makeTown() -> Entity {
        let town = Entity()
        town.name = "LowPolyTown"

        let top = baseHeight
        town.addChild(box(size: [baseSize, baseHeight, baseSize], color: Palette.grass, at: [0, baseHeight / 2, 0]))
        addRoads(to: town, top: top)

        for building in buildings {
            town.addChild(makeBuilding(building, top: top))
        }

        let trunkMesh = MeshResource.generateCylinder(height: 0.025, radius: 0.006)
        let foliageMesh = MeshResource.generateCone(height: 0.06, radius: 0.024)
        for position in treePositions {
            town.addChild(makeTree(at: position, top: top, trunkMesh: trunkMesh, foliageMesh: foliageMesh))
        }

        return town
    }

    private static func addRoads(to town: Entity, top: Float) {
        let roadThickness: Float = 0.004
        let roadY = top + roadThickness / 2
        town.addChild(box(size: [baseSize, roadThickness, roadWidth], color: Palette.road, at: [0, roadY, 0]))
        town.addChild(box(size: [roadWidth, roadThickness, baseSize], color: Palette.road, at: [0, roadY, 0]))

        // Dashed center lines, skipping the intersection.
        let markY = top + roadThickness + 0.0005
        let dashOffsets: [Float] = [-0.24, -0.17, -0.10, 0.10, 0.17, 0.24]
        for offset in dashOffsets {
            town.addChild(box(size: [0.03, 0.001, 0.005], color: Palette.laneMark, at: [offset, markY, 0]))
            town.addChild(box(size: [0.005, 0.001, 0.03], color: Palette.laneMark, at: [0, markY, offset]))
        }
    }

    private static func makeBuilding(_ building: Building, top: Float) -> Entity {
        let entity = Entity()
        entity.position = [building.x, top, building.z]

        let body = box(size: [building.width, building.height, building.depth],
                       color: building.color,
                       at: [0, building.height / 2, 0])
        body.components.set(GroundingShadowComponent(castsShadow: true))
        entity.addChild(body)

        switch building.roof {
        case .flat:
            let capHeight: Float = 0.008
            entity.addChild(box(size: [building.width + 0.006, capHeight, building.depth + 0.006],
                                color: Palette.roofDark,
                                at: [0, building.height + capHeight / 2, 0]))
        case .cone:
            let roofHeight: Float = 0.045
            let roof = ModelEntity(
                mesh: .generateCone(height: roofHeight, radius: min(building.width, building.depth) * 0.62),
                materials: [material(Palette.roofRed)]
            )
            roof.position = [0, building.height + roofHeight / 2, 0]
            entity.addChild(roof)
        }

        return entity
    }

    private static func makeTree(at position: SIMD2<Float>, top: Float,
                                 trunkMesh: MeshResource, foliageMesh: MeshResource) -> Entity {
        let tree = Entity()
        tree.position = [position.x, top, position.y]

        let trunk = ModelEntity(mesh: trunkMesh, materials: [material(Palette.trunk)])
        trunk.position = [0, 0.0125, 0]
        tree.addChild(trunk)

        let foliage = ModelEntity(mesh: foliageMesh, materials: [material(Palette.foliage)])
        foliage.position = [0, 0.025 + 0.03, 0]
        foliage.components.set(GroundingShadowComponent(castsShadow: true))
        tree.addChild(foliage)

        return tree
    }

    private static func box(size: SIMD3<Float>, color: UIColor, at position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [material(color)])
        entity.position = position
        return entity
    }

    private static func material(_ color: UIColor) -> SimpleMaterial {
        SimpleMaterial(color: color, roughness: 0.85, isMetallic: false)
    }
}
