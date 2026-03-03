/// KeychainHelperTests.swift — Tests for KeychainHelper using a unique test service.
///
/// Note: Uses the real Keychain with a test-specific account prefix to avoid pollution.

import XCTest

@testable import QuinnVoice

final class KeychainHelperTests: XCTestCase {

    /// Unique prefix to avoid polluting the real Keychain.
    private let testAccountPrefix = "com.quinnvoice.test.\(UUID().uuidString.prefix(8))"

    private func testAccount(_ name: String) -> String {
        "\(testAccountPrefix).\(name)"
    }

    override func tearDown() {
        super.tearDown()
        // Clean up test entries
        for suffix in ["save-load", "overwrite", "nonexistent", "delete", "empty"] {
            KeychainHelper.delete(forAccount: testAccount(suffix))
        }
    }

    // MARK: - Save and Load Round-Trip

    func testSaveAndLoad_roundTrip() {
        let account = testAccount("save-load")
        let saved = KeychainHelper.save("test-api-key-123", forAccount: account)
        XCTAssertTrue(saved, "Save should succeed")

        let loaded = KeychainHelper.load(forAccount: account)
        XCTAssertEqual(loaded, "test-api-key-123")
    }

    // MARK: - Overwrite Existing Value

    func testOverwrite_existingValue() {
        let account = testAccount("overwrite")
        KeychainHelper.save("first-value", forAccount: account)
        KeychainHelper.save("second-value", forAccount: account)

        let loaded = KeychainHelper.load(forAccount: account)
        XCTAssertEqual(loaded, "second-value")
    }

    // MARK: - Load Returns Nil for Nonexistent Key

    func testLoad_returnsNilForNonexistentKey() {
        let loaded = KeychainHelper.load(forAccount: testAccount("nonexistent"))
        XCTAssertNil(loaded)
    }

    // MARK: - Delete Removes Value

    func testDelete_removesValue() {
        let account = testAccount("delete")
        KeychainHelper.save("to-be-deleted", forAccount: account)
        XCTAssertNotNil(KeychainHelper.load(forAccount: account))

        let deleted = KeychainHelper.delete(forAccount: account)
        XCTAssertTrue(deleted)

        XCTAssertNil(KeychainHelper.load(forAccount: account))
    }

    func testDelete_nonexistentKey_returnsTrue() {
        // Delete should succeed (or not fail) even for nonexistent keys
        let deleted = KeychainHelper.delete(forAccount: testAccount("nonexistent"))
        XCTAssertTrue(deleted, "Deleting nonexistent key should return true (errSecItemNotFound is OK)")
    }

    // MARK: - Empty String Deletes Entry

    func testSaveEmptyString_deletesEntry() {
        let account = testAccount("empty")
        KeychainHelper.save("some-value", forAccount: account)
        XCTAssertNotNil(KeychainHelper.load(forAccount: account))

        // Saving empty string should remove the entry
        KeychainHelper.save("", forAccount: account)
        XCTAssertNil(KeychainHelper.load(forAccount: account),
                     "Saving empty string should effectively delete the entry")
    }
}
