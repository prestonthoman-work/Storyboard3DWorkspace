//
//  SampleGenerationTests.swift
//  Storyboard3DWorkspaceTests
//

import Testing
@testable import Storyboard3DWorkspace

@MainActor
struct SampleGenerationTests {
    @Test(arguments: [
        ("a red house", SampleObjectCatalog.Kind.house, "red"),
        ("street lamp", .lamp, nil),            // "street" must not match "tree"
        ("some shrubbery", .shrub, nil),
        ("bushes", .shrub, nil),                // plural, and "bus" isn't a car
        ("tall office building", .building, nil),
        ("tree near a house", .tree, nil),      // earliest object word wins
        ("grey rock", .rock, "grey")
    ] as [(String, SampleObjectCatalog.Kind, String?)])
    func promptsMatchWholeWords(prompt: String, kind: SampleObjectCatalog.Kind, color: String?) {
        let match = SampleObjectCatalog.match(prompt)
        #expect(match.kind == kind)
        #expect(match.colorName == color)
    }

    @Test func unmatchedPromptsGetAPlaceholder() async throws {
        let model = try await SampleModelGenerationService().generateObject(prompt: "a dragon")
        #expect(model.recipe == .placeholder(color: nil))
        #expect(model.displayName == "Placeholder")
        #expect(model.note != nil)
    }

    @Test func basePromptsPickTemplates() async throws {
        let service = SampleModelGenerationService()
        #expect(try await service.generateBase(prompt: "desert").recipe == .baseTemplate("sand"))
        #expect(try await service.generateBase(prompt: "a busy city").recipe == .baseTemplate("streets"))
        #expect(try await service.generateBase(prompt: "the moon").recipe == .baseTemplate("grass"))
    }

    @Test func recipesRebuildAndRecolor() throws {
        let recipe = ModelRecipe.sampleObject(kind: "house", color: "red")
        #expect(recipe.makeEntity() != nil)
        #expect(recipe.defaultName == "Red House")
        let blue = recipe.recolored("blue")
        #expect(blue == .sampleObject(kind: "house", color: "blue"))
        #expect(blue.defaultName == "Blue House")
        #expect(recipe.recolored(nil).defaultName == "House")
        #expect(!ModelRecipe.baseTemplate("grass").canRecolor)
        #expect(ModelRecipe.sampleObject(kind: "nonsense", color: nil).makeEntity() == nil)
    }
}
