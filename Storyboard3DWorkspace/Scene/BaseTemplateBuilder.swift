//
//  BaseTemplateBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Builds round base platforms at a nominal 1 m diameter. `WorkspaceScene` scales them to the chosen size.
enum BaseTemplateBuilder {
    private static let radius: Float = 0.5
    private static let thickness: Float = 0.04

    static func make(_ template: BaseTemplate) -> Entity {
        let base = Entity()
        base.name = "Base-\(template.name)"
        switch template {
        case .grass: addGrass(to: base)
        case .streets: addStreets(to: base)
        case .sand: addSand(to: base)
        case .plaza: addPlaza(to: base)
        }
        return base
    }

    private static func disc(_ color: UIColor) -> ModelEntity {
        LowPoly.cylinder(height: thickness, radius: radius, color, at: [0, thickness / 2, 0])
    }

    private static func addGrass(to base: Entity) {
        base.addChild(disc(UIColor(red: 0.60, green: 0.75, blue: 0.50, alpha: 1)))
    }

    private static func addStreets(to base: Entity) {
        addGrass(to: base)
        let road = UIColor(red: 0.36, green: 0.37, blue: 0.40, alpha: 1)
        let mark = UIColor(red: 0.96, green: 0.90, blue: 0.62, alpha: 1)
        let roadWidth: Float = 0.13
        let roadHeight: Float = 0.006
        // Shortened so the road's corners stay inside the round edge.
        let roadLength = 2 * (radius * radius - (roadWidth / 2) * (roadWidth / 2)).squareRoot() - 0.01
        let y = thickness + roadHeight / 2
        base.addChild(LowPoly.box([roadLength, roadHeight, roadWidth], road, at: [0, y, 0]))
        base.addChild(LowPoly.box([roadWidth, roadHeight, roadLength], road, at: [0, y, 0]))

        let markY = thickness + roadHeight + 0.0008
        for offset: Float in [-0.40, -0.29, -0.18, 0.18, 0.29, 0.40] {
            base.addChild(LowPoly.box([0.06, 0.0015, 0.009], mark, at: [offset, markY, 0]))
            base.addChild(LowPoly.box([0.009, 0.0015, 0.06], mark, at: [0, markY, offset]))
        }
    }

    private static func addSand(to base: Entity) {
        let sand = UIColor(red: 0.88, green: 0.78, blue: 0.58, alpha: 1)
        let dune = UIColor(red: 0.85, green: 0.74, blue: 0.53, alpha: 1)
        base.addChild(disc(sand))
        let dunes: [(SIMD3<Float>, Float)] = [([-0.20, 0, -0.17], 0.14), ([0.22, 0, 0.16], 0.12), ([0.15, 0, -0.25], 0.08)]
        for (position, size) in dunes {
            let mound = LowPoly.sphere(radius: size, dune, at: [position.x, thickness, position.z])
            mound.scale = [1, 0.18, 1]
            base.addChild(mound)
        }
    }

    /// Concentric paving rings with radial joints, like a round town square.
    private static func addPlaza(to base: Entity) {
        let grout = UIColor(red: 0.55, green: 0.54, blue: 0.52, alpha: 1)
        let tileA = UIColor(red: 0.78, green: 0.77, blue: 0.74, alpha: 1)
        let tileB = UIColor(red: 0.72, green: 0.71, blue: 0.68, alpha: 1)
        base.addChild(disc(grout))

        // Each ring is a slightly smaller disc stacked a hair higher, so the visible bands
        // alternate tile and grout without overlapping surfaces flickering.
        let rings: [(radius: Float, color: UIColor)] = [
            (0.485, tileA), (0.370, grout), (0.362, tileB), (0.245, grout), (0.237, tileA), (0.115, grout), (0.107, tileB)
        ]
        for (index, ring) in rings.enumerated() {
            let height: Float = 0.001
            let y = thickness + Float(index) * height + height / 2
            base.addChild(LowPoly.cylinder(height: height, radius: ring.radius, ring.color, at: [0, y, 0]))
        }

        let jointY = thickness + Float(rings.count) * 0.001 + 0.0005
        for angle in stride(from: Float(0), to: .pi, by: .pi / 4) {
            let joint = LowPoly.box([0.97, 0.001, 0.006], grout, at: [0, jointY, 0])
            joint.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
            base.addChild(joint)
        }
    }
}
