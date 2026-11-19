import XCTest
import UIKit
import SwiftUI
import HarnessgramFonts
import HarnessgramHouseCore
@testable import HarnessgramHouseKit

/// A token sheet in the stone and the night theme: every colour, every type style, the arch, the window states, the
/// ruler, the badge and the buttons. The PNGs are written to /private/tmp/harnessgram-house-snapshots when that folder
/// exists (the opt-in pattern of the font snapshots), for a look by eye; the test also holds that it renders.
@available(iOS 16.0, *)
private struct HouseTokenSheet: View {
    let dark: Bool

    var body: some View {
        let p = HouseTokens.colors(darkAppearance: self.dark)
        let swatches: [(String, HouseColor)] = [
            ("bg", p.bg), ("surface", p.surface), ("raised", p.surfaceRaised), ("border", p.border), ("ink", p.ink), ("ink2", p.ink2), ("ink3", p.ink3),
            ("cedar", p.cedar), ("brass", p.brass), ("amber", p.amber), ("amberDeep", p.amberDeep), ("olive", p.olive),
            ("working", p.statusWorking), ("idle", p.statusIdle), ("error", p.statusError),
        ]
        return VStack(alignment: .trailing, spacing: HouseTokens.Space.md) {
            Text("בוקר טוב").houseFont(.display).foregroundColor(p.ink.color)
            Text("שם חדר בעברית").houseFont(.title2).foregroundColor(p.ink.color)
            Text("מחכה לך, בעבודה, שקט").houseFont(.callout).foregroundColor(p.ink2.color)
            Text("בראשית ברא אלקים את השמים ואת הארץ").houseFont(.reading).foregroundColor(p.ink.color)
            Text("12:45  3  17").houseFont(.caption).foregroundColor(p.ink3.color)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(swatches, id: \.0) { item in
                    RoundedRectangle(cornerRadius: 6).fill(item.1.color).frame(height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(p.borderStrong.color, lineWidth: 1))
                }
            }
            HStack(spacing: 12) {
                ArchShape().fill(p.surface.color).frame(width: 60, height: 80).overlay(ArchShape().stroke(p.borderStrong.color, lineWidth: 1))
                WindowStatusView(state: .lit, accessibilityText: "").frame(height: 32)
                WindowStatusView(state: .waiting, accessibilityText: "").frame(height: 32)
                WindowStatusView(state: .dim, accessibilityText: "").frame(height: 32)
                LanternBadge(count: 3)
            }
            ProgressRuler(fraction: 0.55)
            HStack(spacing: 12) {
                Button("אישור") {}.buttonStyle(HouseButtonStyle(.olive))
                Button("אחר כך") {}.buttonStyle(HouseButtonStyle(.outline))
            }
        }
        .padding(HouseTokens.Space.lg)
        .frame(width: 390)
        .background(p.bg.color)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.colorScheme, self.dark ? .dark : .light)
    }
}

final class HouseKitSnapshotTests: XCTestCase {
    @MainActor
    func testTheTokenSheetRendersInBothThemes() throws {
        guard #available(iOS 16.0, *) else {
            throw XCTSkip("ImageRenderer needs iOS 16")
        }
        HarnessgramFonts.registerBundledFonts()
        let folder = "/private/tmp/harnessgram-house-snapshots"
        for dark in [false, true] {
            let renderer = ImageRenderer(content: HouseTokenSheet(dark: dark))
            renderer.scale = 2.0
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 390.0, accuracy: 0.5)
            XCTAssertGreaterThan(image.size.height, 300.0)
            if FileManager.default.fileExists(atPath: folder), let data = image.pngData() {
                try data.write(to: URL(fileURLWithPath: folder + "/house-token-sheet-\(dark ? "night" : "stone").png"))
            }
        }
    }
}
