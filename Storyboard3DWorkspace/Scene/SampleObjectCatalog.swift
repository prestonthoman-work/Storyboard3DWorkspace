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
    private static let foliage = UIColor(red: 0.33, green: 0.58, blue: 0.36, alpha: 1)
    private static let trunk = UIColor(red: 0.47, green: 0.34, blue: 0.24, alpha: 1)

    private static func addHouse(to object: Entity, tint: UIColor?) {
        let wallHeight: Float = 0.05
        object.addChild(LowPoly.box([0.07, wallHeight, 0.06], tint ?? cream, at: [0, wallHeight / 2, 0]))
        if let roofMesh = LowPoly.gableRoof(width: 0.08, depth: 0.07, height: 0.035) {
            // A tinted house gets a neutral roof so the walls' color reads clearly.
            let roof = ModelEntity(mesh: roofMesh, materials: [LowPoly.material(tint == nil ? roofRed : darkGray)])
            roof.position = [0, wallHeight, 0]
            object.addChild(roof)
        }
        object.addChild(LowPoly.box([0.014, 0.024, 0.002], trunk, at: [0, 0.012, 0.0305]))
        object.addChild(LowPoly.box([0.012, 0.014, 0.002], UIColor(red: 0.62, green: 0.78, blue: 0.88, alpha: 1),
                                    at: [0.022, 0.03, 0.0305]))
        object.addChild(LowPoly.box([0.01, 0.03, 0.01], darkGray, at: [-0.022, wallHeight + 0.022, -0.012]))
    }

    private static func addTree(to object: Entity, tint: UIColor?) {
        object.addChild(LowPoly.cylinder(height: 0.03, radius: 0.006, trunk, at: [0, 0.015, 0]))
        object.addChild(LowPoly.cone(height: 0.05, radius: 0.028, tint ?? foliage, at: [0, 0.055, 0]))
        object.addChild(LowPoly.cone(height: 0.04, radius: 0.02, tint ?? foliage, at: [0, 0.085, 0]))
    }

    private static func addShrub(to object: Entity, tint: UIColor?) {
        let color = tint ?? UIColor(red: 0.40, green: 0.64, blue: 0.38, alpha: 1)
        let puffs: [(SIMD3<Float>, Float)] = [([0, 0.014, 0], 0.018), ([0.016, 0.011, 0.006], 0.014), ([-0.014, 0.011, -0.004], 0.015)]
        for (position, radius) in puffs {
            object.addChild(LowPoly.sphere(radius: radius, color, at: position))
        }
    }

    private static func addBuilding(to object: Entity, tint: UIColor?) {
        let height: Float = 0.16
        let color = tint ?? UIColor(red: 0.55, green: 0.63, blue: 0.74, alpha: 1)
        object.addChild(LowPoly.box([0.06, height, 0.06], color, at: [0, height / 2, 0]))
        object.addChild(LowPoly.box([0.066, 0.008, 0.066], darkGray, at: [0, height + 0.004, 0]))
        let glass = UIColor(red: 0.80, green: 0.88, blue: 0.94, alpha: 1)
        for level in 0..<5 {
            let y = 0.025 + Float(level) * 0.028
            object.addChild(LowPoly.box([0.048, 0.01, 0.002], glass, at: [0, y, 0.0305]))
            object.addChild(LowPoly.box([0.002, 0.01, 0.048], glass, at: [0.0305, y, 0]))
        }
    }

    private static func addCar(to object: Entity, tint: UIColor?) {
        let color = tint ?? UIColor(red: 0.80, green: 0.30, blue: 0.27, alpha: 1)
        object.addChild(LowPoly.box([0.06, 0.014, 0.028], color, at: [0, 0.012, 0], cornerRadius: 0.003))
        object.addChild(LowPoly.box([0.032, 0.012, 0.024], UIColor(red: 0.80, green: 0.88, blue: 0.94, alpha: 1),
                                    at: [-0.004, 0.025, 0], cornerRadius: 0.003))
        for x: Float in [-0.019, 0.019] {
            for z: Float in [-0.0145, 0.0145] {
                let wheel = LowPoly.cylinder(height: 0.005, radius: 0.0065, darkGray, at: [x, 0.0065, z])
                wheel.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                object.addChild(wheel)
            }
        }
    }

    private static func addLamp(to object: Entity, tint: UIColor?) {
        let pole = tint ?? darkGray
        object.addChild(LowPoly.cylinder(height: 0.004, radius: 0.007, pole, at: [0, 0.002, 0]))
        object.addChild(LowPoly.cylinder(height: 0.075, radius: 0.0022, pole, at: [0, 0.0375, 0]))
        let bulb = ModelEntity(mesh: .generateSphere(radius: 0.007),
                               materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.92, blue: 0.70, alpha: 1))])
        bulb.position = [0, 0.08, 0]
        object.addChild(bulb)
    }

    private static func addFence(to object: Entity, tint: UIColor?) {
        let color = tint ?? UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
        for i in 0..<5 {
            object.addChild(LowPoly.box([0.004, 0.03, 0.004], color, at: [-0.04 + Float(i) * 0.02, 0.015, 0]))
        }
        for y: Float in [0.011, 0.023] {
            object.addChild(LowPoly.box([0.086, 0.004, 0.003], color, at: [0, y, 0]))
        }
    }

    private static func addRock(to object: Entity, tint: UIColor?) {
        let color = tint ?? UIColor(red: 0.58, green: 0.57, blue: 0.55, alpha: 1)
        let large = LowPoly.sphere(radius: 0.02, color, at: [0, 0.012, 0])
        large.scale = [1.2, 0.7, 1]
        object.addChild(large)
        let small = LowPoly.sphere(radius: 0.011, color, at: [0.022, 0.006, 0.01])
        small.scale = [1, 0.7, 1.1]
        object.addChild(small)
    }

    private static func addShadows(to object: Entity) {
        for child in object.children {
            child.components.set(GroundingShadowComponent(castsShadow: true))
        }
    }
}
