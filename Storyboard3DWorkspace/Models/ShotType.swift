//
//  ShotType.swift
//  Storyboard3DWorkspace
//

import Foundation

/// The standard framing vocabulary of a storyboard, so every panel says how it's shot.
enum ShotType: String, Codable, CaseIterable, Identifiable {
    case establishing
    case wide
    case medium
    case closeUp
    case extremeCloseUp
    case overTheShoulder
    case pointOfView
    case aerial

    var id: String { rawValue }

    var name: String {
        switch self {
        case .establishing: "Establishing"
        case .wide: "Wide"
        case .medium: "Medium"
        case .closeUp: "Close-Up"
        case .extremeCloseUp: "Extreme Close-Up"
        case .overTheShoulder: "Over the Shoulder"
        case .pointOfView: "Point of View"
        case .aerial: "Aerial"
        }
    }

    /// The short form printed on storyboard panels.
    var abbreviation: String {
        switch self {
        case .establishing: "EST"
        case .wide: "WS"
        case .medium: "MS"
        case .closeUp: "CU"
        case .extremeCloseUp: "ECU"
        case .overTheShoulder: "OTS"
        case .pointOfView: "POV"
        case .aerial: "AERIAL"
        }
    }

    var symbol: String {
        switch self {
        case .establishing: "building.2"
        case .wide: "rectangle.expand.vertical"
        case .medium: "person.crop.rectangle"
        case .closeUp: "person.crop.square"
        case .extremeCloseUp: "eye"
        case .overTheShoulder: "person.2"
        case .pointOfView: "eyes"
        case .aerial: "airplane"
        }
    }
}
