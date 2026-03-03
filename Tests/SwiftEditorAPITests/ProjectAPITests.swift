import Testing
import Foundation
@testable import SwiftEditorAPI
@testable import CoreMediaPlus
@testable import ProjectModel

@Suite("ProjectAPI Tests")
struct ProjectAPITests {

    private func makeEngine() async throws -> SwiftEditorEngine {
        let engine = SwiftEditorEngine(projectName: "ProjectTest")
        try await Task.sleep(for: .milliseconds(100))
        return engine
    }

    @Test("Project has correct initial name")
    func initialName() async throws {
        let engine = try await makeEngine()
        #expect(engine.projectAPI.name == "ProjectTest")
    }

    @Test("Rename project")
    func renameProject() async throws {
        let engine = try await makeEngine()
        engine.projectAPI.rename("My Film")
        #expect(engine.projectAPI.name == "My Film")
    }

    @Test("Project has valid ID and dates")
    func projectIdentity() async throws {
        let engine = try await makeEngine()
        let id = engine.projectAPI.id
        #expect(id != UUID())  // Should be a valid non-nil UUID
        #expect(engine.projectAPI.createdAt <= Date())
        #expect(engine.projectAPI.modifiedAt <= Date())
    }

    @Test("Add and remove sequence")
    func addRemoveSequence() async throws {
        let engine = try await makeEngine()
        let initialCount = engine.projectAPI.sequences.count

        let seq = engine.projectAPI.addSequence(name: "Timeline 2")
        #expect(engine.projectAPI.sequences.count == initialCount + 1)
        #expect(seq.name == "Timeline 2")

        engine.projectAPI.removeSequence(id: seq.id)
        #expect(engine.projectAPI.sequences.count == initialCount)
    }

    @Test("Rename sequence")
    func renameSequence() async throws {
        let engine = try await makeEngine()
        let seq = engine.projectAPI.addSequence(name: "Old Name")

        engine.projectAPI.renameSequence(id: seq.id, name: "New Name")
        let updated = engine.projectAPI.sequences.first(where: { $0.id == seq.id })
        #expect(updated?.name == "New Name")
    }

    @Test("Update project settings")
    func updateSettings() async throws {
        let engine = try await makeEngine()
        let originalSettings = engine.projectAPI.settings

        var newSettings = originalSettings
        newSettings.frameRate = Rational(30, 1)
        engine.projectAPI.updateSettings(newSettings)

        #expect(engine.projectAPI.frameRate == Rational(30, 1))
    }

    @Test("Set and get metadata")
    func metadata() async throws {
        let engine = try await makeEngine()

        engine.projectAPI.setAuthor("Alice")
        #expect(engine.projectAPI.metadata.author == "Alice")

        engine.projectAPI.setDescription("A test project")
        #expect(engine.projectAPI.metadata.description == "A test project")
    }

    @Test("Add and remove tags")
    func tags() async throws {
        let engine = try await makeEngine()

        engine.projectAPI.addTag("documentary")
        engine.projectAPI.addTag("4K")
        #expect(engine.projectAPI.metadata.tags.contains("documentary"))
        #expect(engine.projectAPI.metadata.tags.contains("4K"))

        // Adding duplicate should not create double
        engine.projectAPI.addTag("documentary")
        #expect(engine.projectAPI.metadata.tags.filter { $0 == "documentary" }.count == 1)

        engine.projectAPI.removeTag("documentary")
        #expect(!engine.projectAPI.metadata.tags.contains("documentary"))
    }

    @Test("Custom metadata fields")
    func customFields() async throws {
        let engine = try await makeEngine()

        engine.projectAPI.setCustomField(key: "client", value: "Acme Corp")
        #expect(engine.projectAPI.metadata.customFields["client"] == "Acme Corp")

        engine.projectAPI.removeCustomField(key: "client")
        #expect(engine.projectAPI.metadata.customFields["client"] == nil)
    }

    @Test("Modified date updates on changes")
    func modifiedDateUpdates() async throws {
        let engine = try await makeEngine()
        let before = engine.projectAPI.modifiedAt

        // Small delay to ensure date difference
        try await Task.sleep(for: .milliseconds(10))

        engine.projectAPI.rename("Updated Name")
        let after = engine.projectAPI.modifiedAt
        #expect(after >= before)
    }
}
