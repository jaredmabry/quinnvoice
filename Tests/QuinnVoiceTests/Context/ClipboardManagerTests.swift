/// ClipboardManagerTests.swift — Tests for ClipboardManager pasteboard operations.

import AppKit
import XCTest

@testable import QuinnVoice

@MainActor
final class ClipboardManagerTests: XCTestCase {

    private var manager: ClipboardManager!

    override func setUp() {
        super.setUp()
        manager = ClipboardManager()
    }

    override func tearDown() {
        manager.stopMonitoring()
        manager = nil
        super.tearDown()
    }

    // MARK: - Get Clipboard

    func testGetClipboard_returnsCurrentPasteboardString() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("test clipboard content", forType: .string)

        let result = manager.getClipboard()
        XCTAssertEqual(result, "test clipboard content")
    }

    // MARK: - Set Clipboard

    func testSetClipboard_writesToPasteboard() {
        let result = manager.setClipboard("new content")
        XCTAssertTrue(result.contains("success") || result.contains("updated"),
                      "Should confirm clipboard was updated")

        let pasteboardContent = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasteboardContent, "new content")
    }

    // MARK: - Round-Trip

    func testClipboard_roundTrip() {
        _ = manager.setClipboard("round-trip test")
        let result = manager.getClipboard()
        XCTAssertEqual(result, "round-trip test")
    }

    // MARK: - Empty Pasteboard

    func testGetClipboard_emptyPasteboard() {
        NSPasteboard.general.clearContents()
        let result = manager.getClipboard()
        // Should return a descriptive message, not crash
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Set Empty String

    func testSetClipboard_emptyString() {
        _ = manager.setClipboard("")
        // Should not crash; pasteboard will have empty string or be considered empty
        let result = manager.getClipboard()
        XCTAssertNotNil(result)
    }

    // MARK: - Monitoring

    func testStartMonitoring_setsFlag() {
        XCTAssertFalse(manager.isMonitoring)
        manager.startMonitoring()
        XCTAssertTrue(manager.isMonitoring)
    }

    func testStopMonitoring_clearsFlag() {
        manager.startMonitoring()
        manager.stopMonitoring()
        XCTAssertFalse(manager.isMonitoring)
    }

    func testStartMonitoring_idempotent() {
        manager.startMonitoring()
        manager.startMonitoring()
        XCTAssertTrue(manager.isMonitoring)
    }

    func testStopMonitoring_idempotent() {
        manager.stopMonitoring()
        manager.stopMonitoring()
        XCTAssertFalse(manager.isMonitoring)
    }

    // MARK: - Current Content

    func testCurrentContent_initiallyNil() {
        XCTAssertNil(manager.currentContent)
    }

    func testCurrentContent_updatedAfterGet() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("track me", forType: .string)

        _ = manager.getClipboard()
        XCTAssertEqual(manager.currentContent, "track me")
    }

    func testCurrentContent_updatedAfterSet() {
        _ = manager.setClipboard("set content")
        XCTAssertEqual(manager.currentContent, "set content")
    }
}
