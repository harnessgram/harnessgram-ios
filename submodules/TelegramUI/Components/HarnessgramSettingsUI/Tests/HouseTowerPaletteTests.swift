import XCTest
import SwiftUI
import UIKit
@testable import HarnessgramSettingsUI
import HarnessgramCockpitKit
import HarnessgramHouseCore

/// Build 31 (owner: "Dark version only?? Everything should support light mode too"): the tower Cockpit has a day look
/// and a night look from one palette. Every text colour keeps WCAG AA on the page and the cards in both; the night look
/// keeps the build 30 numbers. Renders of the tab in both looks land in
/// /private/tmp/harnessgram-widget-snapshots/tower when that folder's parent exists.
@available(iOS 16.0, *)
final class HouseTowerPaletteTests: XCTestCase {
    private static func luminance(_ hex: UInt32) -> Double {
        func linear(_ v: UInt32) -> Double {
            let c = Double(v) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear((hex >> 16) & 0xff) + 0.7152 * linear((hex >> 8) & 0xff) + 0.0722 * linear(hex & 0xff)
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testEveryTextColourKeepsAAInTheDayAndTheNightLook() {
        for (name, text) in HouseTowerPalette.Tones.textColors {
            for (backgroundName, background) in HouseTowerPalette.Tones.textBackgrounds {
                let day = HouseTowerPaletteTests.contrast(text.light, background.light)
                let night = HouseTowerPaletteTests.contrast(text.dark, background.dark)
                XCTAssertGreaterThanOrEqual(day, 4.5, "light \(name) on \(backgroundName): \(day)")
                XCTAssertGreaterThanOrEqual(night, 4.5, "dark \(name) on \(backgroundName): \(night)")
            }
        }
        // The bars and dials stand out from their track (WCAG 1.4.11, 3:1) in both looks.
        for fill in [HouseTowerPalette.Tones.accent, HouseTowerPalette.Tones.approve] {
            XCTAssertGreaterThanOrEqual(HouseTowerPaletteTests.contrast(fill.light, HouseTowerPalette.Tones.track.light), 3.0)
            XCTAssertGreaterThanOrEqual(HouseTowerPaletteTests.contrast(fill.dark, HouseTowerPalette.Tones.track.dark), 3.0)
        }
    }

    func testTheNightLookIsUnchangedAndTheDayLookIsLight() {
        XCTAssertEqual(HouseTowerPalette.Tones.background.dark, 0x0C161E)
        XCTAssertEqual(HouseTowerPalette.Tones.skyTop.dark, 0x14232D)
        XCTAssertEqual(HouseTowerPalette.Tones.primaryText.dark, 0xFFFFFF)
        XCTAssertEqual(HouseTowerPalette.Tones.accent.dark, 0x5EEAC4)
        XCTAssertGreaterThan(HouseTowerPaletteTests.luminance(HouseTowerPalette.Tones.background.light), 0.8)
        XCTAssertLessThan(HouseTowerPaletteTests.luminance(HouseTowerPalette.Tones.primaryText.light), 0.05)
        // The UIKit page colour follows the appearance.
        let page = HouseTowerPalette.backgroundUIColor
        XCTAssertNotEqual(page.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)), page.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
    }

    private static let folder = URL(fileURLWithPath: "/private/tmp/harnessgram-widget-snapshots/tower", isDirectory: true)

    @MainActor
    private func render<V: View>(_ view: V, size: CGSize, dark: Bool) -> UIImage? {
        let framed = view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.layoutDirection, .rightToLeft)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// The tower tab (phone and wide list) in both looks, with the demo Cockpit: what the owner sees before a build.
    @MainActor
    func testTheTowerTabRendersInTheDayAndTheNightLook() {
        if FileManager.default.fileExists(atPath: HouseTowerPaletteTests.folder.deletingLastPathComponent().path) {
            try? FileManager.default.createDirectory(at: HouseTowerPaletteTests.folder, withIntermediateDirectories: true)
        }
        let tab = HarnessgramCockpitTabViewModel.make(snapshot: .houseDemo, openDecisions: nil, isPaired: true, isPaused: false)
        let empty = HarnessgramCockpitTabViewModel.make(snapshot: nil, openDecisions: nil, isPaired: false, isPaused: false)
        let cases: [(String, AnyView, CGSize)] = [
            ("phone-tower", AnyView(HouseCockpitPhoneTowerView(model: HouseCockpitTabModel(preview: tab, statusBarHeight: 47), radio: .shared, scrolls: false)), CGSize(width: 393, height: 2500)),
            ("phone-tower-pairing", AnyView(HouseCockpitPhoneTowerView(model: HouseCockpitTabModel(preview: empty, statusBarHeight: 47), radio: .shared, scrolls: false)), CGSize(width: 393, height: 852)),
            ("wide-tower-list", AnyView(HouseCockpitTowerListView(model: HouseCockpitTabModel(preview: tab, isRegularWidth: true), radio: .shared, scrolls: false)), CGSize(width: 420, height: 1500)),
        ]
        for (name, view, size) in cases {
            for dark in [false, true] {
                let image = self.render(view, size: size, dark: dark)
                XCTAssertNotNil(image, name)
                if let image, let data = image.pngData(), FileManager.default.fileExists(atPath: HouseTowerPaletteTests.folder.path) {
                    try? data.write(to: HouseTowerPaletteTests.folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }
}
