//
//  ModelRecipeBuilder.swift
//  Storyboard3DWorkspace
//

import Foundation
import RealityKit

extension ModelRecipe {
    /// The name sample mode gives this content, such as "Red House".
    var defaultName: String? {
        let prefix = colorName.map { "\($0.capitalized) " } ?? ""
        switch self {
        case .sampleObject(let kind, _):
            return SampleObjectCatalog.Kind(rawValue: kind).map { prefix + $0.name }
        case .placeholder:
            return prefix + "Placeholder"
        case .baseTemplate(let name):
            return BaseTemplate(rawValue: name)?.name
        }
    }

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
