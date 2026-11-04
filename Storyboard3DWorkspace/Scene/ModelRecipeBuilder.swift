//
//  ModelRecipeBuilder.swift
//  Storyboard3DWorkspace
//

import RealityKit

extension ModelRecipe {
    /// Rebuilds the content a recipe describes. Returns nil if it can't be rebuilt.
    func makeEntity() -> Entity? {
        switch self {
        case .sampleObject(let kind, let color):
            guard let kind = SampleObjectCatalog.Kind(rawValue: kind) else { return nil }
            return SampleObjectCatalog.make(kind, tint: SampleObjectCatalog.color(named: color))
        case .placeholder(let color):
            return SampleObjectCatalog.makePlaceholder(tint: SampleObjectCatalog.color(named: color))
        case .baseTemplate(let name):
            guard let template = BaseTemplate(rawValue: name) else { return nil }
            return BaseTemplateBuilder.make(template)
        }
    }
}
