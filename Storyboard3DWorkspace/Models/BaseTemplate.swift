//
//  BaseTemplate.swift
//  Storyboard3DWorkspace
//

import SwiftUI

/// Built-in platforms that objects are placed on.
enum BaseTemplate: String, CaseIterable, Identifiable {
    case grass
    case streets
    case sand
    case plaza

    var id: String { rawValue }

    var name: String {
        switch self {
        case .grass: "Grass"
        case .streets: "Streets"
        case .sand: "Sand"
        case .plaza: "Plaza"
        }
    }

    var symbol: String {
        switch self {
        case .grass: "leaf"
        case .streets: "road.lanes"
        case .sand: "sun.max"
        case .plaza: "square.grid.3x3"
        }
    }

    var swatch: Color {
        switch self {
        case .grass: Color(red: 0.60, green: 0.75, blue: 0.50)
        case .streets: Color(red: 0.45, green: 0.50, blue: 0.48)
        case .sand: Color(red: 0.88, green: 0.78, blue: 0.58)
        case .plaza: Color(red: 0.74, green: 0.73, blue: 0.70)
        }
    }

    /// Words that steer sample-mode base generation toward this template.
    var keywords: [String] {
        switch self {
        case .grass: ["grass", "park", "field", "lawn", "meadow", "garden", "forest"]
        case .streets: ["street", "road", "city", "town", "village", "intersection"]
        case .sand: ["sand", "desert", "beach", "dune"]
        case .plaza: ["plaza", "stone", "square", "courtyard", "tile", "paved", "patio"]
        }
    }
}

enum BaseSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Width of the square base, in meters.
    var meters: Float {
        switch self {
        case .small: 0.4
        case .medium: 0.6
        case .large: 0.8
        }
    }

    var label: String {
        switch self {
        case .small: "40 cm"
        case .medium: "60 cm"
        case .large: "80 cm"
        }
    }
}
