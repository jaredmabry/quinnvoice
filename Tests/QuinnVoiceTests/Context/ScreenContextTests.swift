/// ScreenContextTests.swift — Tests for ScreenContextProvider.

import XCTest

@testable import QuinnVoice

@MainActor
final class ScreenContextTests: XCTestCase {

    // MARK: - Frontmost App Detection

    func testCaptureContext_returnsNonNil() {
        let provider = ScreenContextProvider()
        let context = provider.captureContext()
        // In a test environment there should be a frontmost app (xctest/Xcode)
        XCTAssertNotNil(context)
    }

    func testCaptureContext_hasAppName() {
        let provider = ScreenContextProvider()
        guard let context = provider.captureContext() else {
            // If running headless with no GUI, skip
            return
        }
        XCTAssertFalse(context.appName.isEmpty)
    }

    func testFrontmostAppName_returnsNonNil() {
        let provider = ScreenContextProvider()
        let appName = provider.frontmostAppName()
        // Should return something in a GUI test environment
        XCTAssertNotNil(appName)
    }

    // MARK: - Context String Formatting

    func testScreenContext_description_containsAppName() {
        let context = ScreenContextProvider.ScreenContext(
            appName: "Safari",
            windowTitle: "Google",
            selectedText: nil
        )

        XCTAssertTrue(context.description.contains("Safari"))
        XCTAssertTrue(context.description.contains("Google"))
        XCTAssertTrue(context.description.contains("User is currently viewing"))
    }

    func testScreenContext_description_withoutWindowTitle() {
        let context = ScreenContextProvider.ScreenContext(
            appName: "Finder",
            windowTitle: nil,
            selectedText: nil
        )

        XCTAssertTrue(context.description.contains("Finder"))
        XCTAssertTrue(context.description.contains("User is currently viewing"))
    }

    func testScreenContext_description_withEmptyWindowTitle() {
        let context = ScreenContextProvider.ScreenContext(
            appName: "Terminal",
            windowTitle: "",
            selectedText: nil
        )

        // Empty window title should be treated like nil
        XCTAssertTrue(context.description.contains("Terminal"))
        XCTAssertFalse(context.description.contains(" — "))
    }

    func testScreenContext_description_withSelectedText() {
        let context = ScreenContextProvider.ScreenContext(
            appName: "Xcode",
            windowTitle: "main.swift",
            selectedText: "let x = 42"
        )

        XCTAssertTrue(context.description.contains("Xcode"))
        XCTAssertTrue(context.description.contains("main.swift"))
        XCTAssertTrue(context.description.contains("Selected text"))
        XCTAssertTrue(context.description.contains("let x = 42"))
    }

    func testScreenContext_description_truncatesLongSelectedText() {
        let longText = String(repeating: "A", count: 600)
        let context = ScreenContextProvider.ScreenContext(
            appName: "TextEdit",
            windowTitle: "doc.txt",
            selectedText: longText
        )

        XCTAssertTrue(context.description.contains("…"))
        // The truncated text should be <= 500 chars + ellipsis
    }

    // MARK: - Graceful Handling When No Window Is Focused

    func testCaptureContext_doesNotCrash() {
        let provider = ScreenContextProvider()
        // Call multiple times — should never crash
        for _ in 0..<5 {
            _ = provider.captureContext()
            _ = provider.captureContext(includeSelectedText: false)
        }
    }

    func testCaptureContext_withoutSelectedText() {
        let provider = ScreenContextProvider()
        let context = provider.captureContext(includeSelectedText: false)
        // Should still work, just without selected text
        if let context {
            XCTAssertNil(context.selectedText)
            XCTAssertFalse(context.appName.isEmpty)
        }
    }

    // MARK: - Accessibility Permissions

    func testHasAccessibilityPermissions_doesNotCrash() {
        // Just verify the static method doesn't crash (don't prompt)
        _ = ScreenContextProvider.hasAccessibilityPermissions(prompt: false)
    }
}
