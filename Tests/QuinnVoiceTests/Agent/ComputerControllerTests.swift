/// ComputerControllerTests.swift — Tests for ComputerController virtual key code mapping
/// and event construction. Does NOT require Accessibility permissions.

import XCTest

@testable import QuinnVoice

final class ComputerControllerTests: XCTestCase {

    // MARK: - Virtual Key Code Mapping: Letters

    func testVirtualKeyCode_a() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "a"), 0)
    }

    func testVirtualKeyCode_s() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "s"), 1)
    }

    func testVirtualKeyCode_d() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "d"), 2)
    }

    func testVirtualKeyCode_z() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "z"), 6)
    }

    func testVirtualKeyCode_allLetters() {
        let expected: [(String, UInt16)] = [
            ("a", 0), ("b", 11), ("c", 8), ("d", 2), ("e", 14),
            ("f", 3), ("g", 5), ("h", 4), ("i", 34), ("j", 38),
            ("k", 40), ("l", 37), ("m", 46), ("n", 45), ("o", 31),
            ("p", 35), ("q", 12), ("r", 15), ("s", 1), ("t", 17),
            ("u", 32), ("v", 9), ("w", 13), ("x", 7), ("y", 16),
            ("z", 6),
        ]

        for (key, code) in expected {
            XCTAssertEqual(ComputerController.virtualKeyCode(for: key), code,
                           "Key '\(key)' should map to \(code)")
        }
    }

    // MARK: - Special Keys

    func testVirtualKeyCode_return() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "return"), 36)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "enter"), 36)
    }

    func testVirtualKeyCode_tab() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "tab"), 48)
    }

    func testVirtualKeyCode_space() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "space"), 49)
    }

    func testVirtualKeyCode_escape() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "escape"), 53)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "esc"), 53)
    }

    func testVirtualKeyCode_delete() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "delete"), 51)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "backspace"), 51)
    }

    // MARK: - Arrow Keys

    func testVirtualKeyCode_arrowKeys() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "left"), 123)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "right"), 124)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "down"), 125)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "up"), 126)
    }

    // MARK: - Function Keys

    func testVirtualKeyCode_functionKeys() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "f1"), 122)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "f2"), 120)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "f3"), 99)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "f12"), 111)
    }

    // MARK: - Number Keys

    func testVirtualKeyCode_numberKeys() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "0"), 29)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "1"), 18)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "9"), 25)
    }

    // MARK: - Punctuation

    func testVirtualKeyCode_punctuation() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "-"), 27)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "="), 24)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "["), 33)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "]"), 30)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: ";"), 41)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: ","), 43)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "."), 47)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "/"), 44)
    }

    // MARK: - Navigation Keys

    func testVirtualKeyCode_navigationKeys() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "home"), 115)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "end"), 119)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "pageup"), 116)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "pagedown"), 121)
    }

    // MARK: - Unknown Keys

    func testVirtualKeyCode_unknownKey_returnsZero() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "unknown"), 0)
    }

    // MARK: - Case Insensitivity

    func testVirtualKeyCode_caseInsensitive() {
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "Return"), 36)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "ESCAPE"), 53)
        XCTAssertEqual(ComputerController.virtualKeyCode(for: "Tab"), 48)
    }

    // MARK: - Key Combo Construction (Cmd+S scenario)

    func testKeyCombo_commandS_keyCodes() {
        // Verify the key codes that would be used for Cmd+S
        let sKey = ComputerController.virtualKeyCode(for: "s")
        XCTAssertEqual(sKey, 1)
        // The modifier flag would be .maskCommand (CGEventFlags)
    }

    func testKeyCombo_commandZ_keyCodes() {
        let zKey = ComputerController.virtualKeyCode(for: "z")
        XCTAssertEqual(zKey, 6)
    }

    // MARK: - ControlError

    func testControlError_descriptions() {
        let errors: [ComputerController.ControlError] = [
            .accessibilityNotGranted,
            .elementNotFound("test element"),
            .actionFailed("test action"),
            .screenshotFailed,
            .commandFailed("test command"),
            .appNotFound("TestApp"),
            .timeout,
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testControlError_accessibilityNotGranted_message() {
        let error = ComputerController.ControlError.accessibilityNotGranted
        XCTAssertTrue(error.errorDescription!.contains("Accessibility"))
    }

    func testControlError_appNotFound_containsAppName() {
        let error = ComputerController.ControlError.appNotFound("MyApp")
        XCTAssertTrue(error.errorDescription!.contains("MyApp"))
    }
}
