import XCTest
@testable import AICoven

/// Integration-style tests for MemoryService using the real MemoryRepository
/// and EmbeddingService (which will no-op if no providers are configured).
@MainActor
final class MemoryServiceIntegrationTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await DataEncryptionService.shared.unlockForTestingEphemeral()
        DatabaseManager.shared.configureIfNeeded()
    }

    override func tearDown() async throws {
        await DataEncryptionService.shared.lock()
        try await super.tearDown()
    }

    func testCreateMemoryPersistsChunk() async throws {
        let service = MemoryService(memoryStore: MemoryRepository.shared)

        let scope = "integration_scope_" + UUID().uuidString
        let content = "Memory content for integration test"
        let tags = ["one", "two"]

        let memory = try await service.createMemory(
            covenId: nil,
            scope: scope,
            title: "Test Title",
            content: content,
            tags: tags,
            isPinned: false
        )

        XCTAssertEqual(memory.scope, .user)
        XCTAssertEqual(memory.content, content)
        XCTAssertEqual(memory.tags ?? [], tags)

        // Verify it can be loaded back through the MemoryRepository.
        let chunks = try await MemoryRepository.shared.loadMemories(scope: scope, limit: 10)
        XCTAssertTrue(chunks.contains(where: { $0.id == memory.id && $0.text == content }))
    }

    func testUpdateMemoryFallsBackToExistingTextWhenContentNil() async throws {
        let service = MemoryService(memoryStore: MemoryRepository.shared)

        let scope = "integration_update_scope_" + UUID().uuidString
        let originalContent = "Original text"
        let tags = ["alpha"]

        let created = try await service.createMemory(
            covenId: nil,
            scope: scope,
            title: nil,
            content: originalContent,
            tags: tags,
            isPinned: false
        )

        // Update without providing new content; MemoryService should preserve the
        // original text and only update tags/metadata.
        let updated = try await service.updateMemory(
            memoryId: created.id,
            title: nil,
            content: nil,
            tags: ["beta"],
            scope: scope,
            isPinned: true
        )

        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.content, originalContent)
        XCTAssertEqual(updated.tags ?? [], ["beta"])
        XCTAssertTrue(updated.isPinned)
    }

    func testReviewProposalApprove_createsMemoryAndUpdatesStatus() async throws {
        // Arrange: insert a proposal directly via the repository so we exercise
        // the full reviewProposal flow, including MemoryProposalRepository and
        // EmbeddingService.indexMemory.
        let uniqueScope = "proposal_scope_" + UUID().uuidString
        let proposedContent = "Proposed memory content for approve flow"
        let proposedTags = ["tag1", "tag2"]

        let record = try await MemoryProposalRepository.shared.insertProposal(
            eventId: "event-1",
            covenId: nil,
            proposedContent: proposedContent,
            proposedTags: proposedTags,
            scope: uniqueScope,
            reason: "test",
            sourceMessageId: "source-1",
            proposedBy: "tester",
            title: "Test Proposal"
        )

        // Act: approve the proposal via MemoryService.
        let service = MemoryService(memoryStore: MemoryRepository.shared)
        let updated = try await service.reviewProposal(
            proposalId: record.id,
            action: "approve"
        )

        // Assert: proposal status and review metadata are updated.
        XCTAssertEqual(updated.id, record.id)
        XCTAssertEqual(updated.status, "approved")
        XCTAssertEqual(updated.proposedContent, proposedContent)
        XCTAssertEqual(updated.proposedTags ?? [], proposedTags)
        XCTAssertEqual(updated.reviewedBy, "local-user")
        XCTAssertNotNil(updated.reviewedAt)

        // Assert: a corresponding memory chunk was created with the same
        // content/tags under the derived scope.
        let chunks = try await MemoryRepository.shared.loadMemories(scope: uniqueScope, limit: 10)
        XCTAssertTrue(
            chunks.contains(where: { chunk in
                chunk.text == proposedContent && chunk.tags == proposedTags && chunk.scope == uniqueScope
            }),
            "Expected an indexed memory chunk matching the approved proposal"
        )
    }

    func testReviewProposalReject_updatesStatusWithoutCreatingMemory() async throws {
        // Arrange: insert a proposal under a unique scope so we can verify that
        // rejecting it does not create any stored memories.
        let uniqueScope = "proposal_reject_scope_" + UUID().uuidString
        let proposedContent = "Proposed memory content for reject flow"

        let record = try await MemoryProposalRepository.shared.insertProposal(
            eventId: "event-2",
            covenId: nil,
            proposedContent: proposedContent,
            proposedTags: nil,
            scope: uniqueScope,
            reason: nil,
            sourceMessageId: nil,
            proposedBy: "tester",
            title: nil
        )

        let service = MemoryService(memoryStore: MemoryRepository.shared)

        // Act: reject the proposal.
        let updated = try await service.reviewProposal(
            proposalId: record.id,
            action: "reject"
        )

        // Assert: status is updated but no new memories are created for the
        // unique scope.
        XCTAssertEqual(updated.id, record.id)
        XCTAssertEqual(updated.status, "rejected")

        let chunks = try await MemoryRepository.shared.loadMemories(scope: uniqueScope, limit: 10)
        XCTAssertTrue(chunks.isEmpty, "Expected no memory chunks to be created when rejecting a proposal")
    }
}
