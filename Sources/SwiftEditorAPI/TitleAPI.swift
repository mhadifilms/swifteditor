#if canImport(AppKit)
import CoreImage
import Foundation
import CoreMediaPlus
import EffectsEngine

/// Facade for title and text operations.
/// Manages title generators and provides rendering capabilities.
public final class TitleAPI: @unchecked Sendable {
    private let renderer = TitleRenderer()
    private var generators: [UUID: TitleGenerator] = [:]

    public init() {}

    /// Create a title with a template. Returns the generator ID.
    @discardableResult
    public func createTitle(text: String, template: TitleTemplate) -> UUID {
        var t = template
        t.text = text
        let generator = TitleGenerator(template: t)
        let id = UUID()
        generators[id] = generator
        return id
    }

    /// List built-in title templates.
    public var availableTemplates: [TitleTemplate] {
        [
            TitleTemplate.lowerThird(text: ""),
            TitleTemplate.centerTitle(text: ""),
            TitleTemplate.creditsCrawl(text: ""),
        ]
    }

    /// Render a title to an image using a template.
    public func renderTitle(text: String, template: TitleTemplate, size: CGSize) -> CIImage? {
        var t = template
        t.text = text
        return renderer.render(template: t, size: size)
    }

    /// Create a generator for animatable titles.
    @discardableResult
    public func createGenerator(text: String, style: TitleTemplate?, size: CGSize) -> TitleGenerator {
        let template = style ?? TitleTemplate.centerTitle(text: text)
        var t = template
        t.text = text
        let generator = TitleGenerator(template: t)
        let id = UUID()
        generators[id] = generator
        return generator
    }

    /// Update the text of a stored title generator by recreating it.
    public func updateTitleText(generatorID: UUID, text: String) {
        guard let existing = generators[generatorID] else { return }
        var t = existing.template
        t.text = text
        let updated = TitleGenerator(template: t, keyframeTracks: existing.keyframeTracks)
        generators[generatorID] = updated
    }

    /// Change the style of a stored title generator by recreating it.
    public func setTitleStyle(generatorID: UUID, style: TitleTemplate) {
        guard let existing = generators[generatorID] else { return }
        var t = style
        t.text = existing.template.text
        let updated = TitleGenerator(template: t, keyframeTracks: existing.keyframeTracks)
        generators[generatorID] = updated
    }

    /// Get a stored generator by ID.
    public func generator(for id: UUID) -> TitleGenerator? {
        generators[id]
    }

    /// Remove a stored generator.
    public func removeGenerator(_ id: UUID) {
        generators.removeValue(forKey: id)
    }
}
#endif
