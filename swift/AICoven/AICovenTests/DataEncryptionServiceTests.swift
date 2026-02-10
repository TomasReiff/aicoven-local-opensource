import XCTest
@testable import AICoven

/// Tests for the local DataEncryptionService used to protect on-disk data.
final class DataEncryptionServiceTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        // Use the special test-only unlock so we never depend on a real
        // passphrase or device authentication in CI.
        await DataEncryptionService.shared.unlockForTestingEphemeral()
    }

    override func tearDown() async throws {
        await DataEncryptionService.shared.lock()
        try await super.tearDown()
    }

    func testEncryptDecryptRoundtrip_succeedsWithMatchingPurpose() async throws {
        let plaintext = "Hello, encrypted world!".data(using: .utf8)!

        let ciphertext = try await DataEncryptionService.shared.encrypt(plaintext, purpose: "test_purpose")
        XCTAssertNotEqual(ciphertext, plaintext, "Ciphertext should not equal plaintext")

        let decrypted = try await DataEncryptionService.shared.decrypt(ciphertext, purpose: "test_purpose")
        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptFailsWithWrongPurposeAuthentication() async throws {
        let plaintext = "Secret data".data(using: .utf8)!

        let ciphertext = try await DataEncryptionService.shared.encrypt(plaintext, purpose: "right_purpose")

        // Using a different AEAD associated data value should cause
        // AES.GCM to reject the ciphertext with an authentication error.
        do {
            _ = try await DataEncryptionService.shared.decrypt(ciphertext, purpose: "wrong_purpose")
            XCTFail("Expected decrypt to throw when using a different purpose (AEAD auth should fail)")
        } catch {
            // Expected: authentication error from AES.GCM
        }
    }

    func testDecryptFailsWhenKeyLocked() async throws {
        let plaintext = "Another secret".data(using: .utf8)!

        let ciphertext = try await DataEncryptionService.shared.encrypt(plaintext, purpose: "lock_test")

        // Simulate app lock by clearing the in-memory key.
        await DataEncryptionService.shared.lock()

        do {
            _ = try await DataEncryptionService.shared.decrypt(ciphertext, purpose: "lock_test")
            XCTFail("Expected decrypt to throw when key is locked")
        } catch {
            // Expected: requireDataKey() should throw "Encryption key is locked" error.
        }
    }
}
