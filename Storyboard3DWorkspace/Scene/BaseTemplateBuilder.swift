//
//  BaseTemplateBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// Builds base platforms at a nominal 1 m width. `WorkspaceScene` scales them to the chosen size.
enum BaseTemplateBuilder {
    private static let width: Float = 1
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

    private static func slab(_ color: UIColor) -> ModelEntity {
        LowPoly.box([width, thickness, width], color, at: [0, thickness / 2, 0], cornerRadius: 0.012)
    }

    private static func addGrass(to base: Entity) {
        base.addChild(slab(UIColor(red: 0.60, green: 0.75, blue: 0.50, alpha: 1)))
    }

    private static func addStreets(to base: Entity) {
        addGrass(to: base)
        let road = UIColor(red: 0.36, green: 0.37, blue: 0.40, alpha: 1)
        let mark = UIColor(red: 0.96, green: 0.90, blue: 0.62, alpha: 1)
        let roadWidth: Float = 0.13
        let roadHeight: Float = 0.006
        let y = thickness + roadHeight / 2
        base.addChild(LowPoly.box([width, roadHeight, roadWidth], road, at: [0, y, 0]))
        base.addChild(LowPoly.box([roadWidth, roadHeight, width], road, at: [0, y, 0]))

        let markY = thickness + roadHeight + 0.0008
        for offset: Float in [-0.43, -0.31, -0.19, 0.19, 0.31, 0.43] {
            base.addChild(LowPoly.box([0.06, 0.0015, 0.009], mark, at: [offset, markY, 0]))
            base.addChild(LowPoly.box([0.009, 0.0015, 0.06], mark, at: [0, markY, offset]))
        }
    }

    private static func addSand(to base: Entity) {
        let sand = UIColor(red: 0.88, green: 0.78, blue: 0.58, alpha: 1)
        let dune = UIColor(red: 0.85, green: 0.74, blue: 0.53, alpha: 1)
        base.addChild(slab(sand))
        let dunes: [(SIMD3<Float>, Float)] = [([-0.28, 0, -0.25], 0.16), ([0.30, 0, 0.22], 0.13), ([0.25, 0, -0.30], 0.09)]
        for (position, radius) in dunes {
            let mound = LowPoly.sphere(radius: radius, dune, at: [position.x, thickness, position.z])
            mound.scale = [1, 0.18, 1]
            base.addChild(mound)
        }
    }

    private static func addPlaza(to base: Entity) {
        let grout = UIColor(red: 0.55, green: 0.54, blue: 0.52, alpha: 1)
        let tileA = UIColor(red: 0.78, green: 0.77, blue: 0.74, alpha: 1)
        let tileB = UIColor(red: 0.72, green: 0.71, blue: 0.68, alpha: 1)
        base.addChild(slab(grout))

        let count = 6
        let pitch = width / Float(count)
        let tileSize = pitch - 0.008
        for row in 0..<count {
            for column in 0..<count {
                let x = -width / 2 + pitch * (Float(column) + 0.5)
                let z = -width / 2 + pitch * (Float(row) + 0.5)
                let color = (row + column).isMultiple(of: 2) ? tileA : tileB
                base.addChild(LowPoly.box([tileSize, 0.004, tileSize], color, at: [x, thickness + 0.002, z]))
            }
        }
    }
}
