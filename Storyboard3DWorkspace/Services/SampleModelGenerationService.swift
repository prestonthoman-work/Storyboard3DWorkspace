//
//  SampleModelGenerationService.swift
//  Storyboard3DWorkspace
//

import RealityKit

/// Sample mode: ignores the prompt and returns a procedurally built low-poly town.
struct SampleModelGenerationService: ModelGenerationService {
    let source: ModelSource = .sample

    func generateModel(prompt: String) async throws -> GeneratedModel {
        GeneratedModel(
            displayName: "Low-poly Town",
            source: .sample,
            entity: LowPolyTownBuilder.makeTown()
        )
    }
}
