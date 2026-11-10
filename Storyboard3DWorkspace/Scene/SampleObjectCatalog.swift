//
//  SampleObjectCatalog.swift
//  Storyboard3DWorkspace
//

import RealityKit
import UIKit

/// The low-poly objects sample mode can place, matched to prompts by keyword.
///
/// Every object is built to diorama scale, centered on the origin, resting on y = 0.
enum SampleObjectCatalog {
    enum Kind: String, CaseIterable {
        case house, tree, shrub, building, car, lamp, fence, rock

        var name: String {
            switch self {
            case .house: "House"
            case .tree: "Tree"
            case .shrub: "Shrub"
            case .building: "Building"
            case .car: "Car"
            case .lamp: "Street Lamp"
            case .fence: "Fence"
            case .rock: "Rock"
            }
        }

        var keywords: [String] {
            switch self {
            case .house: ["house", "home", "cottage", "cabin", "hut", "barn"]
            case .tree: ["tree", "pine", "oak", "fir", "palm"]
            case .shrub: ["shrub", "shrubbery", "bush", "hedge", "plant", "flower", "greenery"]
            case .building: ["building", "tower", "skyscraper", "office", "apartment", "shop", "store"]
            case .car: ["car", "vehicle", "truck", "taxi", "van", "bus"]
            case .lamp: ["lamp", "streetlight", "street light", "lamppost", "light"]
            case .fence: ["fence", "railing", "wall", "gate"]
            case .rock: ["rock", "stone", "boulder", "pebble"]
            }
        }
    }

    struct Match {
        let kind: Kind?
        let colorName: String?
        let color: UIColor?
        let keyword: String?
    }

    private static let colors: [(String, UIColor)] = [
        ("red", UIColor(red: 0.80, green: 0.30, blue: 0.27, alpha: 1)),
        ("orange", UIColor(red: 0.92, green: 0.56, blue: 0.25, alpha: 1)),
        ("yellow", UIColor(red: 0.95, green: 0.82, blue: 0.35, alpha: 1)),
        ("green", UIColor(red: 0.38, green: 0.62, blue: 0.38, alpha: 1)),
        ("teal", UIColor(red: 0.30, green: 0.62, blue: 0.62, alpha: 1)),
        ("blue", UIColor(red: 0.35, green: 0.52, blue: 0.80, alpha: 1)),
        ("purple", UIColor(red: 0.58, green: 0.44, blue: 0.75, alpha: 1)),
        ("pink", UIColor(red: 0.92, green: 0.62, blue: 0.70, alpha: 1)),
        ("brown", UIColor(red: 0.52, green: 0.38, blue: 0.27, alpha: 1)),
        ("white", UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)),
        ("gray", UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1)),
        ("grey", UIColor(red: 0.55, green: 0.56, blue: 0.58, alpha: 1)),
        ("black", UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1))
    ]

    /// Color names offered for recoloring, in display order.
    static let colorNames = colors.map(\.0).filter { $0 != "grey" }

    static func color(named name: String?) -> UIColor? {
        guard let name else { return nil }
        return colors.first { $0.0 == name }?.1
    }

    static func match(_ prompt: String) -> Match {
        let words = words(in: prompt)
        // Pick the object word that appears earliest in the prompt ("tree near a house" -> tree).
        var best: (kind: Kind, keyword: String, position: Int)?
        for kind in Kind.allCases {
            for keyword in kind.keywords {
                if let position = position(of: keyword, in: words), best.map({ position < $0.position }) ?? true {
                    best = (kind, keyword, position)
                }
            }
        }
        let color = colors.first { position(of: $0.0, in: words) != nil }
        return Match(kind: best?.kind, colorName: color?.0, color: color?.1, keyword: best?.keyword)
    }

    static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// Index of the first whole-word match (plurals allowed), so "street" never matches "tree".
    static func position(of keyword: String, in words: [String]) -> Int? {
        let parts = keyword.split(separator: " ").map(String.init)
        guard !parts.isEmpty, words.count >= parts.count else { return nil }
        for start in 0...(words.count - parts.count) {
            let matches = parts.indices.allSatisfy { offset in
                let word = words[start + offset]
                let part = parts[offset]
                return word == part || word == part + "s" || word == part + "es"
            }
            if matches { return start }
        }
        return nil
    }

    static func make(_ kind: Kind, tint: UIColor?) -> Entity {
        let object = Entity()
        object.name = kind.name
        switch kind {
        case .house: addHouse(to: object, tint: tint)
        case .tree: addTree(to: object, tint: tint)
        case .shrub: addShrub(to: object, tint: tint)
        case .building: addBuilding(to: object, tint: tint)
        case .car: addCar(to: object, tint: tint)
        case .lamp: addLamp(to: object, tint: tint)
        case .fence: addFence(to: object, tint: tint)
        case .rock: addRock(to: object, tint: tint)
        }
        addShadows(to: object)
        return object
    }

    /// A neutral block for prompts that no sample object matches.
    static func makePlaceholder(tint: UIColor?) -> Entity {
        let object = Entity()
        object.name = "Placeholder"
        object.addChild(LowPoly.box([0.04, 0.04, 0.04], tint ?? UIColor(white: 0.75, alpha: 1),
                                    at: [0, 0.02, 0], cornerRadius: 0.004))
        addShadows(to: object)
        return object
    }

    // MARK: Objects

    private static let cream = UIColor(red: 0.95, green: 0.91, blue: 0.82, alpha: 1)
    private static let roofRed = UIColor(red: 0.70, green: 0.32, blue: 0.27, alpha: 1)
    private static let darkGray = UIColor(red: 0.36, green: 0.36, blue: 0.38, alpha: 1)
    private static let charcoal = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
    private static let trim = UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
    private static let foliage = UIColor(red: 0.33, green: 0.58, blue: 0.36, alpha: 1)
    private static let trunk = UIColor(red: 0.47, green: 0.34, blue: 0.24, alpha: 1)
    private static let wood = UIColor(red: 0.42, green: 0.27, blue: 0.18, alpha: 1)
    /// Dark blue-gray, so windows read as glass reflecting the sky.
    private static let glass = UIColor(red: 0.40, green: 0.52, blue: 0.64, alpha: 1)
    private static let warmLight = UIColor(red: 1, green: 0.86, blue: 0.58, alpha: 1)

    /// The same hue, lighter or darker, for shading variations within one object.
    private static func shade(_ color: UIColor, _ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(max(b * amount, 0), 1), alpha: a)
    }

    private static func addHouse(to object: Entity, tint: UIColor?) {
        let wallHeight: Float = 0.05
        let walls = tint ?? cream
        // A slightly darker plinth course grounds the walls.
        object.addChild(LowPoly.box([0.072, 0.004, 0.062], shade(walls, 0.78), at: [0, 0.002, 0]))
        object.addChild(LowPoly.box([0.07, wallHeight - 0.004, 0.06], walls, at: [0, 0.004 + (wallHeight - 0.004) / 2, 0]))
        if let roofMesh = LowPoly.gableRoof(width: 0.08, depth: 0.07, height: 0.035) {
            // A tinted house gets a neutral roof so the walls' color reads clearly.
            let roof = ModelEntity(mesh: roofMesh, materials: [LowPoly.material(tint == nil ? roofRed : darkGray, .satin)])
            roof.position = [0, wallHeight, 0]
            object.addChild(roof)
        }
        // Door with a frame and a little step.
        object.addChild(LowPoly.box([0.017, 0.027, 0.0016], trim, at: [0, 0.0175, 0.0303], finish: .satin))
        object.addChild(LowPoly.box([0.013, 0.024, 0.002], wood, at: [0, 0.016, 0.0308], finish: .satin))
        object.addChild(LowPoly.box([0.02, 0.003, 0.006], shade(walls, 0.7), at: [0, 0.0015, 0.033]))
        // Framed glass windows on the front and sides.
        let windows: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0.022, 0.032, 0.0303], [0.0125, 0.0135, 0.0016]),
            ([-0.022, 0.032, 0.0303], [0.0125, 0.0135, 0.0016]),
            ([0.0353, 0.03, 0.01], [0.0016, 0.0135, 0.0125]),
            ([-0.0353, 0.03, -0.01], [0.0016, 0.0135, 0.0125])
        ]
        for (position, size) in windows {
            object.addChild(LowPoly.box(size, trim, at: position, finish: .satin))
            let inset = SIMD3<Float>(size.x > 0.005 ? size.x - 0.003 : size.x + 0.0006,
                                     size.y - 0.003,
                                     size.z > 0.005 ? size.z - 0.003 : size.z + 0.0006)
            object.addChild(LowPoly.box(inset, glass, at: position, finish: .glass))
        }
        object.addChild(LowPoly.box([0.01, 0.03, 0.01], shade(darkGray, 0.9), at: [-0.022, wallHeight + 0.022, -0.012]))
        object.addChild(LowPoly.box([0.012, 0.003, 0.012], charcoal, at: [-0.022, wallHeight + 0.037, -0.012]))
    }

    private static func addTree(to object: Entity, tint: UIColor?) {
        let leaves = tint ?? foliage
        object.addChild(LowPoly.cylinder(height: 0.032, radius: 0.0055, trunk, at: [0, 0.016, 0]))
        // Three tiers, darker at the bottom where they'd be shaded.
        object.addChild(LowPoly.cone(height: 0.045, radius: 0.03, shade(leaves, 0.82), at: [0, 0.05, 0], finish: .satin))
        object.addChild(LowPoly.cone(height: 0.04, radius: 0.024, leaves, at: [0, 0.071, 0], finish: .satin))
        object.addChild(LowPoly.cone(height: 0.032, radius: 0.016, shade(leaves, 1.12), at: [0, 0.091, 0], finish: .satin))
    }

    private static func addShrub(to object: Entity, tint: UIColor?) {
        let color = tint ?? UIColor(red: 0.40, green: 0.64, blue: 0.38, alpha: 1)
        let puffs: [(SIMD3<Float>, Float, CGFloat)] = [
            ([0, 0.018, 0], 0.018, 1.0), ([0.016, 0.014, 0.006], 0.014, 0.88),
            ([-0.014, 0.015, -0.004], 0.015, 0.92), ([0.004, 0.028, -0.005], 0.011, 1.12)
        ]
        for (position, radius, brightness) in puffs {
            object.addChild(LowPoly.sphere(radius: radius, shade(color, brightness), at: position, finish: .satin))
        }
        // A few tiny blossoms.
        if tint == nil {
            for position: SIMD3<Float> in [[0.008, 0.033, 0.006], [-0.01, 0.026, 0.01], [0.02, 0.022, -0.002]] {
                object.addChild(LowPoly.sphere(radius: 0.0022, UIColor(red: 0.98, green: 0.86, blue: 0.9, alpha: 1), at: position))
            }
        }
    }

    private static func addBuilding(to object: Entity, tint: UIColor?) {
        let height: Float = 0.16
        let color = tint ?? UIColor(red: 0.55, green: 0.63, blue: 0.74, alpha: 1)
        // Darker ground-floor base, the tower, and a metal parapet and rooftop unit.
        object.addChild(LowPoly.box([0.064, 0.02, 0.064], shade(color, 0.7), at: [0, 0.01, 0], finish: .satin))
        object.addChild(LowPoly.box([0.06, height - 0.02, 0.06], color, at: [0, 0.02 + (height - 0.02) / 2, 0], finish: .satin))
        object.addChild(LowPoly.box([0.066, 0.006, 0.066], UIColor(white: 0.62, alpha: 1), at: [0, height + 0.003, 0], finish: .metal))
        object.addChild(LowPoly.box([0.022, 0.012, 0.016], UIColor(white: 0.7, alpha: 1), at: [0.008, height + 0.012, -0.008], finish: .metal))
        // Lobby glass, then bands of windows on every face.
        object.addChild(LowPoly.box([0.04, 0.013, 0.002], glass, at: [0, 0.008, 0.0325], finish: .glass))
        for level in 0..<5 {
            let y = 0.034 + Float(level) * 0.025
            object.addChild(LowPoly.box([0.05, 0.012, 0.002], glass, at: [0, y, 0.0305], finish: .glass))
            object.addChild(LowPoly.box([0.05, 0.012, 0.002], glass, at: [0, y, -0.0305], finish: .glass))
            object.addChild(LowPoly.box([0.002, 0.012, 0.05], glass, at: [0.0305, y, 0], finish: .glass))
            object.addChild(LowPoly.box([0.002, 0.012, 0.05], glass, at: [-0.0305, y, 0], finish: .glass))
        }
    }

    private static func addCar(to object: Entity, tint: UIColor?) {
        let paint = tint ?? UIColor(red: 0.80, green: 0.30, blue: 0.27, alpha: 1)
        // Lower body, then the cabin: painted roof over a band of glass.
        object.addChild(LowPoly.box([0.06, 0.013, 0.028], paint, at: [0, 0.0125, 0], cornerRadius: 0.004, finish: .gloss))
        object.addChild(LowPoly.box([0.028, 0.0085, 0.0225], glass, at: [-0.004, 0.0222, 0], cornerRadius: 0.0025, finish: .glass))
        object.addChild(LowPoly.box([0.031, 0.0028, 0.0255], paint, at: [-0.004, 0.0275, 0], cornerRadius: 0.0012, finish: .gloss))
        // Pillars between the windows tie the roof to the body.
        for x: Float in [-0.0165, 0.0085] {
            object.addChild(LowPoly.box([0.0022, 0.0085, 0.0232], paint, at: [x, 0.0222, 0], finish: .gloss))
        }
        // Bumpers, headlights, and taillights.
        object.addChild(LowPoly.box([0.002, 0.004, 0.026], charcoal, at: [0.0305, 0.0085, 0], finish: .satin))
        object.addChild(LowPoly.box([0.002, 0.004, 0.026], charcoal, at: [-0.0305, 0.0085, 0], finish: .satin))
        for z: Float in [-0.009, 0.009] {
            object.addChild(LowPoly.box([0.0016, 0.003, 0.006], warmLight, at: [0.0302, 0.0145, z], finish: .glow))
            object.addChild(LowPoly.box([0.0016, 0.0025, 0.006], UIColor(red: 0.85, green: 0.1, blue: 0.08, alpha: 1),
                                        at: [-0.0302, 0.0145, z], finish: .glow))
        }
        // Tires with metal hubs.
        for x: Float in [-0.019, 0.019] {
            for z: Float in [-0.0145, 0.0145] {
                let tire = LowPoly.cylinder(height: 0.005, radius: 0.0065, charcoal, at: [x, 0.0065, z])
                tire.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                object.addChild(tire)
                let hub = LowPoly.cylinder(height: 0.0054, radius: 0.0032, UIColor(white: 0.75, alpha: 1),
                                           at: [x, 0.0065, z], finish: .metal)
                hub.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                object.addChild(hub)
            }
        }
    }

    private static func addLamp(to object: Entity, tint: UIColor?) {
        let pole = tint ?? charcoal
        object.addChild(LowPoly.cylinder(height: 0.005, radius: 0.0075, pole, at: [0, 0.0025, 0], finish: .metal))
        object.addChild(LowPoly.cylinder(height: 0.072, radius: 0.0021, pole, at: [0, 0.041, 0], finish: .metal))
        object.addChild(LowPoly.cone(height: 0.008, radius: 0.0085, pole, at: [0, 0.0855, 0], finish: .metal))
        let bulb = LowPoly.sphere(radius: 0.0055, warmLight, at: [0, 0.0795, 0], finish: .glow)
        // A small warm light that actually lights what's around the lamp.
        var light = PointLightComponent(color: warmLight, intensity: 400, attenuationRadius: 0.14)
        light.attenuationFalloffExponent = 2
        bulb.components.set(light)
        object.addChild(bulb)
    }

    private static func addFence(to object: Entity, tint: UIColor?) {
        let color = tint ?? UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
        for i in 0..<5 {
            let x = -0.04 + Float(i) * 0.02
            object.addChild(LowPoly.box([0.004, 0.028, 0.004], color, at: [x, 0.014, 0], finish: .satin))
            // Pointed caps on each picket.
            let cap = LowPoly.cone(height: 0.005, radius: 0.0029, color, at: [x, 0.0305, 0], finish: .satin)
            cap.orientation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
            object.addChild(cap)
        }
        for y: Float in [0.01, 0.022] {
            object.addChild(LowPoly.box([0.086, 0.004, 0.003], shade(color, 0.92), at: [0, y, -0.0025], finish: .satin))
        }
    }

    private static func addRock(to object: Entity, tint: UIColor?) {
        let color = tint ?? UIColor(red: 0.58, green: 0.57, blue: 0.55, alpha: 1)
        var builder = MeshBuilder()
        builder.addBlob(center: [0, 0.014, 0], radii: [0.024, 0.014, 0.02], rings: 4, segments: 7, twist: 0.3)
        var small = MeshBuilder()
        small.addBlob(center: [0.024, 0.0075, 0.011], radii: [0.011, 0.0075, 0.012], rings: 3, segments: 6, twist: 1.1)
        if let large = builder.makeEntity(named: "Rock", material: LowPoly.material(color)) { object.addChild(large) }
        if let pebble = small.makeEntity(named: "Pebble", material: LowPoly.material(shade(color, 0.85))) { object.addChild(pebble) }
    }

    private static func addShadows(to object: Entity) {
        for child in object.children {
            child.components.set(GroundingShadowComponent(castsShadow: true))
        }
    }
}
