import XCTest
import Foundation
@testable import HarnessgramSettingsUI

/// The house filled button keeps its white label readable on every fill it can show (normal, pressed, disabled), for
/// both roles. Computed from the palette's own numbers with the WCAG 2.x formula.
final class HarnessgramFilledButtonStyleTests: XCTestCase {
    private func luminance(_ hex: UInt32) -> Double {
        func linear(_ value: UInt32) -> Double {
            let c = Double(value & 0xff) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(hex >> 16) + 0.7152 * linear(hex >> 8) + 0.0722 * linear(hex)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = self.luminance(a)
        let lb = self.luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testTheFormulaMatchesKnownValues() {
        XCTAssertEqual(self.contrast(0xFFFFFF, 0x000000), 21.0, accuracy: 0.01)
        XCTAssertEqual(self.contrast(0xFFFFFF, 0xFFFFFF), 1.0, accuracy: 0.001)
        // The reported failure: a light-blue label on the system blue fill is far below AA.
        XCTAssertLessThan(self.contrast(0x9CCBFF, 0x3FA2FF), 2.0)
    }

    func testTheWhiteLabelPassesAAOnEveryFill() {
        XCTAssertEqual(HarnessgramFilledButtonPalette.label, 0xFFFFFF)
        XCTAssertEqual(HarnessgramFilledButtonPalette.allFills.count, 1 + 2 * HarnessgramFilledButtonPalette.Role.allCases.count)
        for fill in HarnessgramFilledButtonPalette.allFills {
            let ratio = self.contrast(HarnessgramFilledButtonPalette.label, fill)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, String(format: "fill %06X: %.2f", fill, ratio))
        }
    }

    func testDisabledAndPressedPickTheirOwnFills() {
        for role in HarnessgramFilledButtonPalette.Role.allCases {
            XCTAssertEqual(HarnessgramFilledButtonPalette.fill(role, pressed: false, enabled: false), HarnessgramFilledButtonPalette.disabledFill)
            XCTAssertEqual(HarnessgramFilledButtonPalette.fill(role, pressed: true, enabled: false), HarnessgramFilledButtonPalette.disabledFill)
            XCTAssertNotEqual(HarnessgramFilledButtonPalette.fill(role, pressed: true, enabled: true), HarnessgramFilledButtonPalette.fill(role, pressed: false, enabled: true))
            XCTAssertNotEqual(HarnessgramFilledButtonPalette.fill(role, pressed: false, enabled: true), HarnessgramFilledButtonPalette.disabledFill)
        }
    }
}
