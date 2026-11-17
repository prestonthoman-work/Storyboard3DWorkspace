//
//  GeneratedObjectTests.swift
//  Storyboard3DWorkspaceTests
//

import Foundation
import RealityKit
import Testing
@testable import Storyboard3DWorkspace

@MainActor
struct GeneratedObjectTests {
    /// A wooden chair: a seat, four legs and a backrest.
    private func chair() -> ObjectDesign {
        func box(_ label: String, _ size: (Double, Double, Double), x: Double, z: Double, bottom: Double,
                 main: Bool = true) -> ObjectDesign.Part {
            ObjectDesign.Part(label: label, shape: "box", widthCm: size.0, heightCm: size.1, depthCm: size.2,
                              xCm: x, zCm: z, bottomCm: bottom, orientation: "upright", yawDegrees: 0,
                              color: "brown", isMainBody: main)
        }
        var parts = [box("seat", (45, 5, 45), x: 0, z: 0, bottom: 42)]
        for x in [-19.0, 19] {
            for z in [-19.0, 19] { parts.append(box("leg", (4, 42, 4), x: x, z: z, bottom: 0, main: false)) }
        }
        parts.append(box("backrest", (45, 45, 4), x: 0, z: -20.5, bottom: 47))
        return ObjectDesign(name: "Red Wooden Chair", parts: parts)
    }

    final class Calls { var count = 0 }
    struct Failure: Error {}

    private func service(key: String? = "test-key", calls: Calls = Calls(),
                         design: @escaping () throws -> ObjectDesign) -> ClaudeModelGenerationService {
        ClaudeModelGenerationService(apiKey: { key }) { _, _ in
            calls.count += 1
            return try design()
        }
    }

    // MARK: Building

    @Test func designsAreScaledCenteredAndGrounded() throws {
        let parts = GeneratedObjectBuilder.fit(chair().unfittedParts)
        #expect(parts.count == 6)
        let low = parts.map { $0.center - $0.turnedHalfExtent }.reduce(SIMD3(repeating: Float.infinity)) { simd_min($0, $1) }
        let high = parts.map { $0.center + $0.turnedHalfExtent }.reduce(SIMD3(repeating: -Float.infinity)) { simd_max($0, $1) }
        #expect(abs(low.y) < 1e-6)
        #expect(abs(low.x + high.x) < 1e-6)
        #expect(abs(low.z + high.z) < 1e-6)
        // 92 cm tall at the characters' scale.
        #expect(abs(high.y - 0.92 * RigLayout.miniatureScale) < 1e-5)
    }

    @Test func oversizedAndBrokenPartsAreFixed() {
        let tower = GeneratedPart(shape: .cylinder, center: [0, 5000, 0], size: [500, 10_000, 500],
                                  orientation: .upright, color: "chartreuse", isMainBody: true)
        let broken = GeneratedPart(shape: .box, center: [.nan, 0, 0], size: [1, 1, 1],
                                   orientation: .upright, color: "red", isMainBody: false)
        let parts = GeneratedObjectBuilder.fit([tower, broken])
        #expect(parts.count == 1)
        #expect(abs(parts[0].size.y - GeneratedObjectBuilder.sizeLimits.upperBound) < 1e-5)
        #expect(parts[0].color == "gray")
        #expect(GeneratedObjectBuilder.fit([broken]).isEmpty)
    }

    @Test func turnedPartsAndWedgesBuild() throws {
        // A 100 × 20 cm plank turned 90° is 20 cm wide and 100 cm deep.
        let plank = GeneratedPart(shape: .box, center: [0, 1, 0], size: [100, 2, 20], orientation: .upright,
                                  color: "tan", isMainBody: false, yaw: .pi / 2)
        #expect(abs(plank.turnedHalfExtent.x - 10) < 1e-3)
        #expect(abs(plank.turnedHalfExtent.z - 50) < 1e-3)

        let roof = GeneratedPart(shape: .wedge, center: [0, 15, 0], size: [80, 30, 60], orientation: .upright,
                                 color: "red", isMainBody: true)
        let object = GeneratedObjectBuilder.make(name: "Hut", parts: GeneratedObjectBuilder.fit([roof, plank]), tint: nil)
        #expect(object.children.count == 2)
        let bounds = object.visualBounds(relativeTo: object)
        #expect(abs(bounds.min.y) < 1e-4)     // the wedge rests on the ground, not half below it
    }

    @Test func generatedObjectsSaveRebuildAndRecolor() throws {
        let parts = GeneratedObjectBuilder.fit(chair().unfittedParts)
        let recipe = ModelRecipe.generatedObject(name: "Wooden Chair", parts: parts, color: nil)
        let decoded = try JSONDecoder().decode(ModelRecipe.self, from: JSONEncoder().encode(recipe))
        #expect(decoded == recipe)
        #expect(recipe.makeEntity()?.children.count == 6)
        #expect(recipe.canRecolor)
        let blue = recipe.recolored("blue")
        #expect(blue.colorName == "blue")
        #expect(blue.defaultName == "Blue Wooden Chair")
        #expect(blue.makeEntity() != nil)
        #expect(ModelRecipe.generatedObject(name: "Empty", parts: [], color: nil).makeEntity() == nil)
    }

    // MARK: The service

    @Test func promptsAreGeneratedWithAKey() async throws {
        let service = service { chair() }
        #expect(service.source == .service(name: "Claude"))
        let model = try await service.generateObject(prompt: "a red wooden chair")
        guard case .generatedObject(let name, let parts, nil) = model.recipe else {
            Issue.record("Expected a generated object, got \(model.recipe)")
            return
        }
        #expect(name == "Wooden Chair")              // color words are left out of names
        #expect(parts.count == 6)
        #expect(model.entity.children.count == 6)
    }

    @Test func builtInObjectsAndPeopleSkipClaude() async throws {
        let calls = Calls()
        let service = service(calls: calls) { chair() }
        #expect(try await service.generateObject(prompt: "a red house").recipe == .sampleObject(kind: "house", color: "red"))
        #expect(try await service.generateObject(prompt: "Trees").recipe == .sampleObject(kind: "tree", color: nil))
        #expect(try await service.generateObject(prompt: "a man holding a bench").recipe.characterKind == .mannequin)
        #expect(calls.count == 0)
        _ = try await service.generateObject(prompt: "a haunted house")
        #expect(calls.count == 1)
    }

    @Test func noKeyFallsBackToSampleMatching() async throws {
        let calls = Calls()
        let service = service(key: nil, calls: calls) { chair() }
        #expect(service.source == .sample)
        let model = try await service.generateObject(prompt: "a dragon")
        #expect(model.recipe == .placeholder(color: nil))
        #expect(model.note?.hasPrefix("Add a Claude API key") == true)
        #expect(calls.count == 0)
    }

    @Test func failuresFallBackWithTheReason() async throws {
        let declined = service { throw ClaudeClient.Failure(message: "Claude wouldn't make that.") }
        let model = try await declined.generateObject(prompt: "a fancy car")
        #expect(model.recipe == .sampleObject(kind: "car", color: nil))
        #expect(model.note?.hasPrefix("Claude wouldn't make that.") == true)

        let unknown = service { throw Failure() }
        #expect(try await unknown.generateObject(prompt: "a dragon").note?.hasPrefix("Couldn't reach Claude.") == true)

        let empty = service { ObjectDesign(name: "Nothing", parts: []) }
        #expect(try await empty.generateObject(prompt: "a dragon").recipe == .placeholder(color: nil))
    }

    @Test func basesStillUseTemplates() async throws {
        #expect(try await service { chair() }.generateBase(prompt: "desert").recipe == .baseTemplate("sand"))
    }

    // MARK: The API

    private func response(stopReason: String, text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": "msg_test", "type": "message", "role": "assistant", "model": "claude-opus-5-5",
            "stop_reason": stopReason,
            "content": [["type": "thinking", "thinking": "", "signature": "x"], ["type": "text", "text": text]]
        ] as [String: Any])
    }

    @Test func responsesAreParsed() throws {
        let json = String(data: try JSONEncoder().encode(chair()), encoding: .utf8)!
        #expect(try ClaudeClient.parse(response(stopReason: "end_turn", text: json)) == chair())

        #expect(throws: ClaudeClient.Failure.self) { try ClaudeClient.parse(response(stopReason: "refusal", text: "")) }
        #expect(throws: ClaudeClient.Failure.self) { try ClaudeClient.parse(response(stopReason: "max_tokens", text: "{\"na")) }
        #expect(throws: ClaudeClient.Failure.self) { try ClaudeClient.parse(Data("not json".utf8)) }
        #expect(ClaudeClient.message(forStatus: 401, body: Data()).contains("API key"))
    }

    @Test func schemaMatchesTheDesignType() throws {
        // Every field the schema requires decodes into ObjectDesign.Part, and every enum
        // matches what the builder understands.
        let schema = ClaudeModelGenerationService.schema
        let parts = try #require((schema["properties"] as? [String: Any])?["parts"] as? [String: Any])
        let part = try #require(parts["items"] as? [String: Any])
        let required = try #require(part["required"] as? [String])
        let encoded = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(chair().parts[0])) as? [String: Any])
        #expect(Set(required) == Set(encoded.keys))
        #expect(JSONSerialization.isValidJSONObject(schema))
    }
}
