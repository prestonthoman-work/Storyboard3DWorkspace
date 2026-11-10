//
//  BaseTemplateBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// The height objects stand at on a base, in the base content's own units. Without it,
/// the top of the base's bounds is used, so raised details (tufts, dunes, planters)
/// would leave objects floating.
struct BaseSurfaceComponent: Component {
    var height: Float
}

/// Builds round diorama bases at a nominal 1 m diameter: a beveled walnut plinth on a
/// dark metal foot, topped with terrain and scattered detail. `WorkspaceScene` scales
/// them to the chosen size.
///
/// Scatter uses a fixed seed per template, so a base looks identical every time it's built.
enum BaseTemplateBuilder {
    private static let radius: Float = 0.5
    private static let thickness: Float = 0.04
    /// Terrain sits inside the plinth's beveled lip.
    private static let terrainRadius: Float = 0.482
    private static let terrainBottom: Float = 0.033

    static func make(_ template: BaseTemplate) -> Entity {
        let base = Entity()
        base.name = "Base-\(template.name)"
        addPlinth(to: base)
        switch template {
        case .grass: addGrass(to: base, seed: 11)
        case .streets: addStreets(to: base)
        case .sand: addSand(to: base)
        case .plaza: addPlaza(to: base)
        }
        base.components.set(BaseSurfaceComponent(height: thickness))
        return base
    }

    // MARK: Plinth

    private static let walnut = UIColor(red: 0.27, green: 0.18, blue: 0.12, alpha: 1)
    private static let walnutLight = UIColor(red: 0.36, green: 0.25, blue: 0.17, alpha: 1)

    private static func addPlinth(to base: Entity) {
        var foot = MeshBuilder()
        foot.addFrustum(bottomRadius: radius + 0.004, topRadius: radius + 0.004, bottomY: 0, topY: 0.005, capBottom: true)
        if let entity = foot.makeEntity(named: "PlinthFoot",
                                        material: LowPoly.material(UIColor(white: 0.11, alpha: 1), .metal)) {
            base.addChild(entity)
        }

        var body = MeshBuilder()
        body.addFrustum(bottomRadius: radius, topRadius: radius - 0.008, bottomY: 0.005, topY: terrainBottom - 0.002,
                        capTop: false)
        if let entity = body.makeEntity(named: "PlinthBody", material: LowPoly.material(walnut, .satin)) {
            base.addChild(entity)
        }

        // The bevel catches the light along the top edge.
        var lip = MeshBuilder()
        lip.addFrustum(bottomRadius: radius - 0.008, topRadius: terrainRadius, bottomY: terrainBottom - 0.002,
                       topY: terrainBottom + 0.001)
        if let entity = lip.makeEntity(named: "PlinthLip", material: LowPoly.material(walnutLight, .satin)) {
            base.addChild(entity)
        }
    }

    /// The terrain disc, its top at exactly `thickness`.
    private static func terrain(_ color: UIColor, finish: LowPoly.Finish = .matte) -> ModelEntity {
        var disc = MeshBuilder()
        disc.addFrustum(bottomRadius: terrainRadius, topRadius: terrainRadius, bottomY: terrainBottom, topY: thickness)
        return disc.makeEntity(named: "Terrain", material: LowPoly.material(color, finish)) ?? ModelEntity()
    }

    private static func add(_ builder: MeshBuilder, _ name: String, _ color: UIColor,
                            _ finish: LowPoly.Finish = .matte, to base: Entity) {
        if let entity = builder.makeEntity(named: name, material: LowPoly.material(color, finish)) {
            base.addChild(entity)
        }
    }

    /// Paper-thin irregular patches of a slightly different color, like worn or lush ground.
    private static func addPatches(to base: Entity, colors: [UIColor], count: Int, radius: ClosedRange<Float>,
                                   reach: Float, random: inout ScatterRandom) {
        var builders = Array(repeating: MeshBuilder(), count: colors.count)
        for index in 0..<count {
            let center = random.pointOnDisc(maxRadius: reach)
            let size = random.float(radius)
            let y = thickness + 0.0003 + Float(index % 3) * 0.0001
            // An irregular polygon reads more natural than a circle.
            let sides = 9
            var points: [SIMD3<Float>] = []
            for i in 0..<sides {
                let angle = Float(i) / Float(sides) * 2 * .pi
                let r = size * random.float(0.7...1.0)
                points.append([center.x + cos(angle) * r, y, center.y + sin(angle) * r * 0.75])
            }
            let middle = SIMD3(center.x, y, center.y)
            for i in 0..<sides {
                builders[index % colors.count].addTriangle(middle, points[i], points[(i + 1) % sides], outward: [0, 1, 0])
            }
        }
        for (builder, color) in zip(builders, colors) {
            add(builder, "Patch", color, to: base)
        }
    }

    // MARK: Templates

    private static let grassGreen = UIColor(red: 0.55, green: 0.71, blue: 0.44, alpha: 1)

    private static func addGrass(to base: Entity, seed: UInt64, keepClear: ((SIMD2<Float>) -> Bool)? = nil) {
        var random = ScatterRandom(seed: seed)
        base.addChild(terrain(grassGreen))
        addPatches(to: base, colors: [UIColor(red: 0.59, green: 0.74, blue: 0.46, alpha: 1),
                                      UIColor(red: 0.52, green: 0.68, blue: 0.42, alpha: 1)],
                   count: 14, radius: 0.04...0.09, reach: 0.42, random: &random)
        addTufts(to: base, count: 280, random: &random, keepClear: keepClear)
        addPebbles(to: base, count: 26, minRadius: 0.3, random: &random, keepClear: keepClear)
        addFlowers(to: base, count: 30, random: &random, keepClear: keepClear)
    }

    /// Clusters of grass blades, denser toward the rim so the middle stays open for objects.
    private static func addTufts(to base: Entity, count: Int, random: inout ScatterRandom,
                                 colors: [UIColor]? = nil, keepClear: ((SIMD2<Float>) -> Bool)? = nil) {
        let palette = colors ?? [UIColor(red: 0.40, green: 0.60, blue: 0.32, alpha: 1),
                                 UIColor(red: 0.48, green: 0.67, blue: 0.36, alpha: 1),
                                 UIColor(red: 0.58, green: 0.72, blue: 0.40, alpha: 1)]
        var builders = Array(repeating: MeshBuilder(), count: palette.count)
        var placed = 0
        while placed < count {
            let point = random.pointOnDisc(maxRadius: terrainRadius - 0.012)
            // Fewer tufts near the middle.
            let edgeBias = simd_length(point) / terrainRadius
            guard random.float(0...1) < 0.25 + edgeBias * 0.9, keepClear?(point) != true else { continue }
            placed += 1
            var builder = builders[placed % palette.count]
            for _ in 0..<Int(random.float(3...5.99)) {
                let offset = SIMD2(random.float(-0.004...0.004), random.float(-0.004...0.004))
                let height = random.float(0.005...0.012)
                builder.addCone(base: [point.x + offset.x, thickness, point.y + offset.y],
                                radius: random.float(0.0012...0.002), height: height, sides: 3,
                                lean: SIMD2(random.float(-0.003...0.003), random.float(-0.003...0.003)),
                                twist: random.float(0...6))
            }
            builders[placed % palette.count] = builder
        }
        for (builder, color) in zip(builders, palette) {
            add(builder, "Tufts", color, .satin, to: base)
        }
    }

    private static func addPebbles(to base: Entity, count: Int, minRadius: Float, random: inout ScatterRandom,
                                   colors: [UIColor]? = nil, keepClear: ((SIMD2<Float>) -> Bool)? = nil) {
        let palette = colors ?? [UIColor(red: 0.62, green: 0.61, blue: 0.58, alpha: 1),
                                 UIColor(red: 0.50, green: 0.49, blue: 0.47, alpha: 1)]
        var builders = Array(repeating: MeshBuilder(), count: palette.count)
        var placed = 0
        while placed < count {
            let point = random.pointOnDisc(minRadius: minRadius, maxRadius: terrainRadius - 0.012)
            guard keepClear?(point) != true else { continue }
            placed += 1
            let size = random.float(0.0025...0.0065)
            builders[placed % palette.count].addBlob(center: [point.x, thickness + size * 0.25, point.y],
                                                     radii: [size, size * 0.55, size * random.float(0.7...1.1)],
                                                     rings: 3, segments: 5, twist: random.float(0...6))
        }
        for (builder, color) in zip(builders, palette) {
            add(builder, "Pebbles", color, to: base)
        }
    }

    private static func addFlowers(to base: Entity, count: Int, random: inout ScatterRandom,
                                   keepClear: ((SIMD2<Float>) -> Bool)? = nil) {
        let palette = [UIColor(red: 0.98, green: 0.97, blue: 0.92, alpha: 1),
                       UIColor(red: 0.98, green: 0.84, blue: 0.35, alpha: 1),
                       UIColor(red: 0.94, green: 0.62, blue: 0.72, alpha: 1)]
        var builders = Array(repeating: MeshBuilder(), count: palette.count)
        var placed = 0
        while placed < count {
            let point = random.pointOnDisc(minRadius: 0.2, maxRadius: terrainRadius - 0.015)
            guard keepClear?(point) != true else { continue }
            placed += 1
            let height = random.float(0.006...0.01)
            builders[placed % palette.count].addBlob(center: [point.x, thickness + height, point.y],
                                                     radii: [0.0019, 0.0016, 0.0019], rings: 3, segments: 5)
        }
        for (builder, color) in zip(builders, palette) {
            add(builder, "Flowers", color, to: base)
        }
    }

    private static func addStreets(to base: Entity) {
        let roadWidth: Float = 0.13
        let halfRoad = roadWidth / 2
        let sidewalk: Float = 0.018
        let clear = halfRoad + sidewalk + 0.006
        // Keep grass detail off the roads and sidewalks.
        addGrass(to: base, seed: 23) { abs($0.x) < clear || abs($0.y) < clear }

        let road = UIColor(red: 0.30, green: 0.31, blue: 0.33, alpha: 1)
        let curb = UIColor(red: 0.78, green: 0.77, blue: 0.74, alpha: 1)
        let mark = UIColor(red: 0.96, green: 0.90, blue: 0.62, alpha: 1)
        let paint = UIColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1)

        // Almost flush with the ground, so objects on the road don't visibly sink.
        let roadTop = thickness + 0.0008
        let length = 2 * (terrainRadius * terrainRadius - (halfRoad + sidewalk) * (halfRoad + sidewalk)).squareRoot() - 0.01

        var asphalt = MeshBuilder()
        asphalt.addBox(center: [0, roadTop - 0.0004, 0], size: [length, 0.0008, roadWidth])
        asphalt.addBox(center: [0, roadTop - 0.0004, 0], size: [roadWidth, 0.0008, length])
        add(asphalt, "Road", road, .satin, to: base)

        // Raised sidewalks along both sides of both roads, stopping at the crossing.
        var walks = MeshBuilder()
        let walkTop = thickness + 0.0022
        let armLength = length / 2 - halfRoad - sidewalk
        for sign: Float in [-1, 1] {
            for side: Float in [-1, 1] {
                let along = sign * (halfRoad + sidewalk + armLength / 2)
                let across = side * (halfRoad + sidewalk / 2)
                walks.addBox(center: [along, walkTop - 0.0011, across], size: [armLength, 0.0022, sidewalk])
                walks.addBox(center: [across, walkTop - 0.0011, along], size: [sidewalk, 0.0022, armLength])
            }
        }
        add(walks, "Sidewalks", curb, to: base)

        // Dashed center lines, then zebra crossings on each approach.
        var lines = MeshBuilder()
        var crossings = MeshBuilder()
        let paintY = roadTop + 0.0002
        for offset: Float in [-0.40, -0.31, -0.22, 0.22, 0.31, 0.40] {
            lines.addBox(center: [offset, paintY, 0], size: [0.05, 0.0004, 0.004])
            lines.addBox(center: [0, paintY, offset], size: [0.004, 0.0004, 0.05])
        }
        for sign: Float in [-1, 1] {
            let distance = halfRoad + 0.018
            for stripe in 0..<7 {
                let lateral = -halfRoad + 0.011 + Float(stripe) * 0.018
                crossings.addBox(center: [sign * distance, paintY, lateral], size: [0.022, 0.0004, 0.008])
                crossings.addBox(center: [lateral, paintY, sign * distance], size: [0.008, 0.0004, 0.022])
            }
        }
        add(lines, "LaneLines", mark, .satin, to: base)
        add(crossings, "Crosswalks", paint, .satin, to: base)

        // A manhole cover adds a little street-level realism.
        var manhole = MeshBuilder()
        manhole.addFrustum(bottomRadius: 0.011, topRadius: 0.011, bottomY: roadTop, topY: roadTop + 0.0004, segments: 24)
        if let entity = manhole.makeEntity(named: "Manhole", material: LowPoly.material(UIColor(white: 0.2, alpha: 1), .metal)) {
            entity.position = [0.17, 0, 0.03]
            base.addChild(entity)
        }
    }

    private static func addSand(to base: Entity) {
        var random = ScatterRandom(seed: 37)
        let sand = UIColor(red: 0.88, green: 0.78, blue: 0.58, alpha: 1)
        base.addChild(terrain(sand))
        addPatches(to: base, colors: [UIColor(red: 0.91, green: 0.82, blue: 0.63, alpha: 1),
                                      UIColor(red: 0.84, green: 0.73, blue: 0.53, alpha: 1)],
                   count: 10, radius: 0.05...0.1, reach: 0.4, random: &random)

        // Low dunes toward the rim.
        var dunes = MeshBuilder()
        for (position, size) in [(SIMD2<Float>(-0.26, -0.22), Float(0.12)), ([0.28, 0.2], 0.1), ([0.2, -0.3], 0.07), ([-0.3, 0.22], 0.08)] {
            dunes.addBlob(center: [position.x, thickness - size * 0.06, position.y],
                          radii: [size, size * 0.14, size * 0.8], rings: 5, segments: 12, twist: 0.4)
        }
        add(dunes, "Dunes", UIColor(red: 0.86, green: 0.75, blue: 0.54, alpha: 1), to: base)

        // Wind ripples: rows of thin, slightly curved ridges.
        var ripples = MeshBuilder()
        for row in -9...9 {
            let z = Float(row) * 0.04 + random.float(-0.006...0.006)
            var x: Float = -0.45
            while x < 0.45 {
                let segment = random.float(0.03...0.06)
                let point = SIMD2(x + segment / 2, z + sin(x * 9 + Float(row)) * 0.008)
                if simd_length(point) < terrainRadius - 0.02 {
                    ripples.addBox(center: [point.x, thickness + 0.0004, point.y],
                                   size: [segment, 0.0008, 0.0016], yaw: cos(x * 9 + Float(row)) * 0.08)
                }
                x += segment + random.float(0.004...0.02)
            }
        }
        add(ripples, "Ripples", UIColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1), to: base)

        addPebbles(to: base, count: 22, minRadius: 0.18, random: &random,
                   colors: [UIColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1),
                            UIColor(red: 0.72, green: 0.62, blue: 0.48, alpha: 1)])
        addTufts(to: base, count: 26, random: &random,
                 colors: [UIColor(red: 0.72, green: 0.66, blue: 0.42, alpha: 1),
                          UIColor(red: 0.60, green: 0.58, blue: 0.36, alpha: 1)]) { simd_length($0) < 0.33 }
    }

    /// Concentric paving rings with radial joints, like a round town square, ringed by planters.
    private static func addPlaza(to base: Entity) {
        let grout = UIColor(red: 0.55, green: 0.54, blue: 0.52, alpha: 1)
        let tileA = UIColor(red: 0.80, green: 0.79, blue: 0.76, alpha: 1)
        let tileB = UIColor(red: 0.73, green: 0.72, blue: 0.69, alpha: 1)
        base.addChild(terrain(grout))

        // Each ring is a slightly smaller disc stacked a hair higher, so the visible bands
        // alternate tile and grout without overlapping surfaces flickering.
        let rings: [(radius: Float, color: UIColor)] = [
            (0.47, tileA), (0.37, grout), (0.364, tileB), (0.245, grout), (0.239, tileA), (0.115, grout), (0.109, tileB)
        ]
        for (index, ring) in rings.enumerated() {
            var disc = MeshBuilder()
            let y = thickness + Float(index + 1) * 0.00012
            disc.addFrustum(bottomRadius: ring.radius, topRadius: ring.radius, bottomY: thickness, topY: y, segments: 72)
            add(disc, "Paving", ring.color, .satin, to: base)
        }

        var joints = MeshBuilder()
        let jointY = thickness + Float(rings.count + 1) * 0.00012
        for angle in stride(from: Float(0), to: .pi, by: .pi / 6) {
            joints.addBox(center: [0, jointY, 0], size: [0.94, 0.0003, 0.004], yaw: angle)
        }
        add(joints, "Joints", grout, to: base)

        // Stone planters with shrubs around the rim.
        var planters = MeshBuilder()
        var soil = MeshBuilder()
        var leaves = MeshBuilder()
        var random = ScatterRandom(seed: 51)
        for index in 0..<8 {
            let angle = Float(index) / 8 * 2 * .pi + .pi / 8
            let center = SIMD2(cos(angle), sin(angle)) * 0.43
            planters.addBox(center: [center.x, thickness + 0.007, center.y], size: [0.04, 0.014, 0.04], yaw: -angle)
            soil.addBox(center: [center.x, thickness + 0.0142, center.y], size: [0.034, 0.0008, 0.034], yaw: -angle)
            for _ in 0..<4 {
                let offset = SIMD2(random.float(-0.01...0.01), random.float(-0.01...0.01))
                let size = random.float(0.008...0.012)
                leaves.addBlob(center: [center.x + offset.x, thickness + 0.015 + size * 0.8, center.y + offset.y],
                               radii: [size, size * 0.9, size], rings: 4, segments: 6, twist: random.float(0...6))
            }
        }
        add(planters, "Planters", UIColor(red: 0.66, green: 0.64, blue: 0.6, alpha: 1), to: base)
        add(soil, "Soil", UIColor(red: 0.3, green: 0.22, blue: 0.16, alpha: 1), to: base)
        add(leaves, "PlanterShrubs", UIColor(red: 0.38, green: 0.6, blue: 0.36, alpha: 1), .satin, to: base)
    }
}
