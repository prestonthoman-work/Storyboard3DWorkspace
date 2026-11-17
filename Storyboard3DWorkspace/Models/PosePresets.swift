//
//  PosePresets.swift
//  Storyboard3DWorkspace
//

import Foundation

/// Ready-made storytelling poses. Applying one changes only the joints, never where the
/// character stands or how big it is, and every joint can be adjusted afterward.
enum PosePreset: String, CaseIterable, Identifiable {
    case standing, sitting, walking, running, pointing, waving, reaching, armsCrossed, crouching, lookingBack

    var id: String { rawValue }

    var name: String {
        switch self {
        case .standing: "Neutral Standing"
        case .sitting: "Sitting"
        case .walking: "Walking Stride"
        case .running: "Running"
        case .pointing: "Pointing"
        case .waving: "Waving"
        case .reaching: "Reaching"
        case .armsCrossed: "Arms Crossed"
        case .crouching: "Crouching"
        case .lookingBack: "Looking Over Shoulder"
        }
    }

    var symbol: String {
        switch self {
        case .standing: "figure.stand"
        case .sitting: "figure.seated.side"
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .pointing: "hand.point.right"
        case .waving: "hand.wave"
        case .reaching: "figure.arms.open"
        case .armsCrossed: "figure.stand.line.dotted.figure.stand"
        case .crouching: "figure.cooldown"
        case .lookingBack: "arrow.uturn.left"
        }
    }

    /// What the pose needs from the scene to read correctly. Nothing is added for you.
    var requirement: String? {
        switch self {
        case .sitting:
            "Needs something to sit on. The feet stay on the ground, so place a prop such as a rock under the hips and size it to knee height."
        default:
            nil
        }
    }

    var pose: CharacterPose {
        switch self {
        case .standing:
            return .neutral
        case .sitting:
            return CharacterPose([
                .spine: .init(bend: 4),
                .leftHip: .init(bend: 90, side: 6), .rightHip: .init(bend: 90, side: 6),
                .leftKnee: .init(bend: 90), .rightKnee: .init(bend: 90),
                .leftShoulder: .init(bend: 22, side: 6), .rightShoulder: .init(bend: 22, side: 6),
                .leftElbow: .init(bend: 55), .rightElbow: .init(bend: 55),
            ])
        case .walking:
            return CharacterPose([
                .chest: .init(twist: -6),
                .leftHip: .init(bend: 25), .leftKnee: .init(bend: 10), .leftAnkle: .init(bend: 15),
                .rightHip: .init(bend: -15), .rightKnee: .init(bend: 25), .rightAnkle: .init(bend: -10),
                .rightShoulder: .init(bend: 22, side: 4), .rightElbow: .init(bend: 20),
                .leftShoulder: .init(bend: -20, side: 4), .leftElbow: .init(bend: 12),
            ])
        case .running:
            return CharacterPose([
                .spine: .init(bend: 12), .chest: .init(twist: -10), .head: .init(bend: -10),
                .leftHip: .init(bend: 55), .leftKnee: .init(bend: 80), .leftAnkle: .init(bend: 20),
                .rightHip: .init(bend: -25), .rightKnee: .init(bend: 65), .rightAnkle: .init(bend: -30),
                .rightShoulder: .init(bend: 50, side: 6), .rightElbow: .init(bend: 95),
                .leftShoulder: .init(bend: -40, side: 6), .leftElbow: .init(bend: 95),
            ], hands: [.left: .fist, .right: .fist])
        case .pointing:
            return CharacterPose([
                .chest: .init(twist: -8),
                .head: .init(twist: -10),
                .rightShoulder: .init(bend: 85, side: 8), .rightWrist: .init(bend: -10),
                .leftShoulder: .init(side: 4), .leftElbow: .init(bend: 8),
            ], hands: [.right: .point])
        case .waving:
            return CharacterPose([
                .head: .init(side: -5),
                .rightShoulder: .init(twist: -90, side: 95), .rightElbow: .init(bend: 95), .rightWrist: .init(side: 15),
                .leftShoulder: .init(side: 4), .leftElbow: .init(bend: 6),
            ], hands: [.right: .open])
        case .reaching:
            return CharacterPose([
                .spine: .init(bend: 10), .chest: .init(bend: 6), .head: .init(bend: -15),
                .leftShoulder: .init(bend: 125, side: 8), .rightShoulder: .init(bend: 125, side: 8),
                .leftElbow: .init(bend: 10), .rightElbow: .init(bend: 10),
                .leftHip: .init(bend: -8), .leftKnee: .init(bend: 6), .leftAnkle: .init(bend: -14),
            ])
        case .armsCrossed:
            return CharacterPose([
                .head: .init(bend: -4),
                .leftShoulder: .init(bend: 32, twist: 75, side: 12), .rightShoulder: .init(bend: 38, twist: 75, side: 12),
                .leftElbow: .init(bend: 110), .rightElbow: .init(bend: 100),
            ])
        case .crouching:
            return CharacterPose([
                .spine: .init(bend: 30), .chest: .init(bend: 10), .head: .init(bend: -30),
                .leftHip: .init(bend: 110, side: 12), .rightHip: .init(bend: 110, side: 12),
                .leftKnee: .init(bend: 130), .rightKnee: .init(bend: 130),
                .leftAnkle: .init(bend: 20), .rightAnkle: .init(bend: 20),
                .leftShoulder: .init(bend: 45, side: 8), .rightShoulder: .init(bend: 45, side: 8),
                .leftElbow: .init(bend: 30), .rightElbow: .init(bend: 30),
            ])
        case .lookingBack:
            return CharacterPose([
                .spine: .init(twist: 12), .chest: .init(twist: 30), .neck: .init(twist: 45), .head: .init(twist: 38, side: 5),
                .leftShoulder: .init(bend: -10, side: 6), .rightShoulder: .init(bend: 12, side: 4),
                .rightElbow: .init(bend: 15),
            ])
        }
    }
}

/// A pose someone saved for reuse, available in every project.
struct SavedPose: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var pose: CharacterPose
}

/// Saved poses, kept in one file beside the projects.
enum PoseLibraryStore {
    private static var file: URL { ProjectStore.storageRoot.appending(path: "Poses.json") }

    static func load() -> [SavedPose] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([SavedPose].self, from: data)) ?? []
    }

    static func save(_ poses: [SavedPose]) throws {
        try FileManager.default.createDirectory(at: ProjectStore.storageRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(poses).write(to: file, options: .atomic)
    }
}
