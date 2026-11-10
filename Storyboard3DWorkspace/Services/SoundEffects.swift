//
//  SoundEffects.swift
//  Storyboard3DWorkspace
//

import RealityKit

/// Short sounds bundled in Resources/Sounds. Played from the entity they belong to, so
/// they come from the right place in the room.
enum SoundEffect: String, CaseIterable {
    case place
    case land
    case grab
    case remove
    case tick
    case shutter
}

enum SoundEffects {
    private static var resources: [SoundEffect: AudioFileResource] = [:]
    private static var loadTask: Task<Void, Never>?

    /// Loads every sound once, in the background. Sounds requested before they finish
    /// loading are skipped.
    static func preload() {
        guard loadTask == nil else { return }
        loadTask = Task {
            for effect in SoundEffect.allCases {
                if let resource = try? await AudioFileResource(named: "\(effect.rawValue).wav") {
                    resources[effect] = resource
                }
            }
        }
    }

    /// - Parameters:
    ///   - gain: Relative loudness in decibels (0 is full volume).
    ///   - pitchVariation: Random pitch spread, so repeated sounds don't feel mechanical.
    static func play(_ effect: SoundEffect, on entity: Entity, gain: Double = 0, pitchVariation: Double = 0.05) {
        guard SceneFeedback.isEnabled, let resource = resources[effect] else { return }
        let controller = entity.playAudio(resource)
        controller.gain = gain
        if pitchVariation > 0 {
            controller.speed = 1 + Double.random(in: -pitchVariation...pitchVariation)
        }
    }
}
