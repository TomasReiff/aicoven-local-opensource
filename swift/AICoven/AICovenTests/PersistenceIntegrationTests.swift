import XCTest
@testable import AICoven

/// Integration-style tests that exercise the real GRDB-backed repositories
/// against DatabaseManager + DataEncryptionService.
@MainActor
final class PersistenceIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Ensure encryption is unlocked and the database is configured
        // before any repository calls.
        await DataEncryptionService.shared.unlockForTestingEphemeral()
        DatabaseManager.shared.configureIfNeeded()
    }

    override func tearDown() async throws {
        await DataEncryptionService.shared.lock()
        try await super.tearDown()
    }

    func testThreadRepository_createThreadAndAppendMessages_roundtrip() async throws {
        let repo = ThreadRepository.shared

        let title = "Integration thread " + UUID().uuidString
        let thread = try await repo.createThread(title: title)

        XCTAssertEqual(thread.title, title)
        XCTAssertFalse(thread.id.isEmpty)

        let userContent = "Hello from integration test"
        let assistantContent = "Reply from assistant"

        _ = try await repo.appendMessage(toThreadID: thread.id, role: "user", content: userContent)
        _ = try await repo.appendMessage(toThreadID: thread.id, role: "assistant", content: assistantContent)

        let loaded = try await repo.loadThread(id: thread.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, thread.id)
        XCTAssertEqual(loaded?.title, title)

        let messages = try await repo.loadMessages(forThreadID: thread.id)
        XCTAssertGreaterThanOrEqual(messages.count, 2)

        // Messages are ordered oldest → newest; verify the last two match what
        // we just wrote and that decryption produced the original content.
        let lastTwo = Array(messages.suffix(2))
        XCTAssertEqual(lastTwo[0].content, userContent)
        XCTAssertEqual(lastTwo[0].role, "user")
        XCTAssertEqual(lastTwo[1].content, assistantContent)
        XCTAssertEqual(lastTwo[1].role, "assistant")
    }

    func testMemoryRepository_storeAndLoad_roundtrip() async throws {
        let repo = MemoryRepository.shared

        let scope = "test_scope_" + UUID().uuidString
        let text = "Persisted memory from integration test"
        let tags = ["integration", "test"]
        let createdBy = "tester"
        let source = "unit-test"

        let stored = try await repo.storeMemory(
            scope: scope,
            text: text,
            tags: tags,
            pii: false,
            createdBy: createdBy,
            source: source,
            embedding: [0.1, 0.2, 0.3]
        )

        XCTAssertEqual(stored.scope, scope)
        XCTAssertEqual(stored.text, text)
        XCTAssertEqual(stored.tags, tags)
        XCTAssertEqual(stored.createdBy, createdBy)
        XCTAssertEqual(stored.source, source)

        let loaded = try await repo.loadMemories(scope: scope, limit: 10)
        XCTAssertFalse(loaded.isEmpty)

        guard let roundTripped = loaded.first(where: { $0.id == stored.id }) else {
            XCTFail("Expected to find stored memory chunk in loadMemories result")
            return
        }

        XCTAssertEqual(roundTripped.scope, scope)
        XCTAssertEqual(roundTripped.text, text)
        XCTAssertEqual(roundTripped.tags, tags)
        XCTAssertEqual(roundTripped.createdBy, createdBy)
        XCTAssertEqual(roundTripped.source, source)
    }
}
