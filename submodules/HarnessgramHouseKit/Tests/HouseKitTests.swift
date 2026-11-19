import XCTest
import UIKit
import SwiftUI
import CoreText
import HarnessgramFonts
import HarnessgramSettings
import HarnessgramHouseCore
@testable import HarnessgramHouseKit

final class HouseKitTests: XCTestCase {
    private final class Anchor {
    }

    private func tokens() throws -> [String: Any] {
        for bundle in [Bundle(for: Anchor.self), Bundle.main] {
            if let url = bundle.url(forResource: "tokens", withExtension: "json"), let data = try? Data(contentsOf: url), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return object
            }
        }
        XCTFail("tokens.json is not in the test bundle")
        return [:]
    }

    private func dictionary(_ object: Any?) -> [String: Any] {
        return object as? [String: Any] ?? [:]
    }

    private func number(_ value: Any?) -> CGFloat {
        return CGFloat((value as? NSNumber)?.doubleValue ?? .nan)
    }

    /// "#RRGGBB" or "rgba(r,g,b,a)".
    private func color(_ text: String) -> HouseColor? {
        if text.hasPrefix("#"), let value = UInt32(text.dropFirst(), radix: 16) {
            return HouseColor(value)
        }
        if text.hasPrefix("rgba(") {
            let parts = text.dropFirst(5).dropLast().split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? .nan }
            if parts.count == 4 {
                return HouseColor((UInt32(parts[0]) << 16) | (UInt32(parts[1]) << 8) | UInt32(parts[2]), alpha: parts[3])
            }
        }
        return nil
    }

    // MARK: tokens equal tokens.json

    func testColoursEqualTokensJSON() throws {
        let colors = self.dictionary(self.dictionary(try self.tokens()["color"]))
        for (name, dark) in [("light", false), ("dark", true)] {
            let table = self.dictionary(colors[name])
            let palette = HouseTokens.colors(darkAppearance: dark)
            let expected: [(String, HouseColor)] = [
                ("bg", palette.bg), ("surface", palette.surface), ("surfaceRaised", palette.surfaceRaised), ("border", palette.border),
                ("borderStrong", palette.borderStrong), ("ink", palette.ink), ("ink2", palette.ink2), ("ink3", palette.ink3),
                ("cedar", palette.cedar), ("cedarDeep", palette.cedarDeep), ("brass", palette.brass), ("amber", palette.amber),
                ("amberGlow", palette.amberGlow), ("amberDeep", palette.amberDeep), ("olive", palette.olive), ("oliveDeep", palette.oliveDeep),
                ("onOlive", palette.onOlive), ("statusWorking", palette.statusWorking), ("statusIdle", palette.statusIdle),
                ("statusWaiting", palette.statusWaiting), ("statusError", palette.statusError), ("scrim", palette.scrim),
            ]
            for (key, value) in expected {
                let text = self.dictionary(table[key])["value"] as? String ?? ""
                XCTAssertEqual(self.color(text), value, "\(name).\(key)")
            }
            // Every colour in the file is covered (the texture asset is not a colour).
            XCTAssertEqual(Set(table.keys).subtracting(["bgStoneTexture"]), Set(expected.map { $0.0 }), name)
        }
        let live = self.dictionary(colors["liveSurfaces"])
        let expectedLive: [(String, HouseColor)] = [
            ("glass", HouseColors.LiveSurfaces.glass), ("progress", HouseColors.LiveSurfaces.progress), ("done", HouseColors.LiveSurfaces.done),
            ("track", HouseColors.LiveSurfaces.track), ("text", HouseColors.LiveSurfaces.text),
        ]
        for (key, value) in expectedLive {
            XCTAssertEqual(self.color(self.dictionary(live[key])["value"] as? String ?? ""), value, "liveSurfaces.\(key)")
        }
    }

    func testSpaceRadiusAndMotionEqualTokensJSON() throws {
        let root = try self.tokens()
        let space = self.dictionary(root["space"])
        let expectedSpace: [(String, CGFloat)] = [
            ("base", HouseTokens.Space.base), ("xs", HouseTokens.Space.xs), ("sm", HouseTokens.Space.sm), ("md", HouseTokens.Space.md),
            ("lg", HouseTokens.Space.lg), ("xl", HouseTokens.Space.xl), ("xxl", HouseTokens.Space.xxl), ("xxxl", HouseTokens.Space.xxxl),
            ("gutterPhone", HouseTokens.Space.gutterPhone), ("gutterTablet", HouseTokens.Space.gutterTablet), ("cardPadding", HouseTokens.Space.cardPadding),
            ("cardGap", HouseTokens.Space.cardGap), ("sectionGap", HouseTokens.Space.sectionGap), ("radioBarInset", HouseTokens.Space.radioBarInset),
            ("minTapTarget", HouseTokens.Space.minTapTarget),
        ]
        for (key, value) in expectedSpace {
            XCTAssertEqual(self.number(space[key]), value, "space.\(key)")
        }
        let radius = self.dictionary(root["radius"])
        let expectedRadius: [(String, CGFloat)] = [
            ("card", HouseTokens.Radius.card), ("roomArt", HouseTokens.Radius.roomArt), ("button", HouseTokens.Radius.button),
            ("chip", HouseTokens.Radius.chip), ("sheetTop", HouseTokens.Radius.sheetTop), ("radioBar", HouseTokens.Radius.radioBar),
        ]
        for (key, value) in expectedRadius {
            XCTAssertEqual(self.number(radius[key]), value, "radius.\(key)")
        }
        let motion = self.dictionary(root["motion"])
        func ms(_ key: String) -> Double {
            return Double(self.number(self.dictionary(motion[key])["duration"])) / 1000.0
        }
        XCTAssertEqual(ms("windowLightOn"), HouseTokens.Motion.windowLightOn, accuracy: 0.0001)
        XCTAssertEqual(ms("windowLightOff"), HouseTokens.Motion.windowLightOff, accuracy: 0.0001)
        XCTAssertEqual(ms("enterRoom"), HouseTokens.Motion.enterRoom, accuracy: 0.0001)
        XCTAssertEqual(ms("knock"), HouseTokens.Motion.knock, accuracy: 0.0001)
        XCTAssertEqual(ms("badgePulse"), HouseTokens.Motion.badgePulse, accuracy: 0.0001)
        XCTAssertEqual(ms("radioWave"), HouseTokens.Motion.radioWave, accuracy: 0.0001)
        XCTAssertEqual(ms("progressFill"), HouseTokens.Motion.progressFill, accuracy: 0.0001)
        XCTAssertTrue((motion["reduceMotion"] as? String ?? "").contains("150ms"))
        XCTAssertEqual(HouseTokens.Motion.reduceMotionFade, 0.150, accuracy: 0.0001)
    }

    func testTypeScaleEqualsTokensJSON() throws {
        let font = self.dictionary(try self.tokens()["font"])
        let scale = self.dictionary(font["scale"])
        let families = self.dictionary(font["family"])
        XCTAssertEqual(Set(scale.keys), Set(HouseTextStyle.allCases.map { $0.rawValue }))
        for style in HouseTextStyle.allCases {
            let entry = self.dictionary(scale[style.rawValue])
            let spec = HouseFont.spec(style)
            XCTAssertEqual(self.number(entry["size"]), spec.size, style.rawValue)
            XCTAssertEqual(self.number(entry["weight"]), spec.weight, style.rawValue)
            XCTAssertEqual(self.number(entry["lineHeight"]), spec.lineHeight, style.rawValue)
            let family = entry["family"] as? String ?? ""
            XCTAssertEqual(families[family] as? String, spec.family.familyName, style.rawValue)
            XCTAssertEqual(spec.family.rawValue, family, style.rawValue)
        }
    }

    // MARK: fonts

    private func familyName(_ font: UIFont) -> String {
        return CTFontCopyFamilyName(font as CTFont) as String
    }

    func testFontsResolveForEveryStyleInTheirFamily() {
        HarnessgramFonts.registerBundledFonts()
        for style in HouseTextStyle.allCases {
            let font = HouseFont.baseFont(style)
            XCTAssertEqual(font.pointSize, HouseFont.spec(style).size, accuracy: 0.01, style.rawValue)
            XCTAssertEqual(self.familyName(font), HouseFont.spec(style).family.familyName, style.rawValue)
        }
    }

    func testTimesAndCountsUseTabularFigures() {
        HarnessgramFonts.registerBundledFonts()
        for style in HouseTextStyle.allCases {
            let features = HouseFont.baseFont(style).fontDescriptor.object(forKey: .featureSettings) as? [[UIFontDescriptor.FeatureKey: Int]]
            let tabular = features?.contains(where: { $0[.type] == kNumberSpacingType && $0[.selector] == kMonospacedNumbersSelector }) ?? false
            XCTAssertEqual(tabular, HouseFont.spec(style).tabularFigures, style.rawValue)
            XCTAssertEqual(tabular, style == .caption || style == .badge, style.rawValue)
        }
    }

    func testScaledSizesGrowUpToAX5() {
        HarnessgramFonts.registerBundledFonts()
        let categories: [UIContentSizeCategory] = [.extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge]
        for style in HouseTextStyle.allCases {
            var previousSize: CGFloat = 0.0
            var previousLine: CGFloat = 0.0
            for category in categories {
                let traits = UITraitCollection(preferredContentSizeCategory: category)
                let size = HouseFont.font(style, compatibleWith: traits).pointSize
                let line = HouseFont.lineHeight(style, compatibleWith: traits)
                XCTAssertGreaterThanOrEqual(size, previousSize, "\(style.rawValue) \(category.rawValue)")
                XCTAssertGreaterThanOrEqual(line, previousLine, "\(style.rawValue) \(category.rawValue)")
                previousSize = size
                previousLine = line
            }
            let large = HouseFont.font(style, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
            XCTAssertEqual(large, HouseFont.spec(style).size, accuracy: 0.6, "the design size is the default size: \(style.rawValue)")
            XCTAssertGreaterThan(previousSize, large * 1.4, "AX5 is clearly larger: \(style.rawValue)")
        }
    }

    func testEveryDynamicTypeSizeMapsToACategoryInOrder() {
        let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge, .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5]
        let scaled = sizes.map { UIFontMetrics(forTextStyle: .body).scaledValue(for: 17.0, compatibleWith: UITraitCollection(preferredContentSizeCategory: HouseFont.contentSizeCategory($0))) }
        XCTAssertEqual(scaled, scaled.sorted())
        XCTAssertEqual(Set(sizes.map { HouseFont.contentSizeCategory($0) }).count, sizes.count)
    }

    // MARK: shapes and art

    func testTheArchTouchesTheTopAndKeepsStraightJambs() {
        let rect = CGRect(x: 10.0, y: 20.0, width: 120.0, height: 160.0)
        for rise in [nil, 60.0, 24.0] as [CGFloat?] {
            let path = ArchShape(rise: rise).path(in: rect)
            let box = path.boundingRect
            XCTAssertEqual(box.minX, rect.minX, accuracy: 0.5)
            XCTAssertEqual(box.maxX, rect.maxX, accuracy: 0.5)
            XCTAssertEqual(box.minY, rect.minY, accuracy: 0.5, "the crown touches the top: \(String(describing: rise))")
            XCTAssertEqual(box.maxY, rect.maxY, accuracy: 0.5)
            XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: rect.minY + 4.0)), "the crown is inside")
            XCTAssertTrue(path.contains(CGPoint(x: rect.minX + 2.0, y: rect.maxY - 2.0)), "the jamb is inside")
            XCTAssertFalse(path.contains(CGPoint(x: rect.minX + 1.0, y: rect.minY + 1.0)), "the corner above the shoulder is outside")
        }
        XCTAssertTrue(ArchShape().path(in: .zero).isEmpty)
    }

    func testArtFitterCropsCentredToTheFrameAspect() {
        let wide = HouseArtFitter.cropRect(imageSize: CGSize(width: 1000.0, height: 400.0), aspect: 1.5)
        XCTAssertEqual(wide.height, 400.0, accuracy: 0.001)
        XCTAssertEqual(wide.width, 600.0, accuracy: 0.001)
        XCTAssertEqual(wide.midX, 500.0, accuracy: 0.001)
        let tall = HouseArtFitter.cropRect(imageSize: CGSize(width: 300.0, height: 900.0), aspect: 1.5)
        XCTAssertEqual(tall.width, 300.0, accuracy: 0.001)
        XCTAssertEqual(tall.height, 200.0, accuracy: 0.001)
        XCTAssertEqual(tall.midY, 450.0, accuracy: 0.001)
        XCTAssertEqual(HouseArtFitter.cropRect(imageSize: CGSize(width: 300.0, height: 200.0), aspect: 0.0), CGRect(x: 0.0, y: 0.0, width: 300.0, height: 200.0))
    }

    func testArtKeysCannotLeaveTheFolder() {
        XCTAssertEqual(HouseArtStore.fileName(for: .gesher), "room-gesher.png")
        XCTAssertNil(HouseArtStore.fileName(for: HouseRoomArtKey(rawValue: "../x")))
        XCTAssertNil(HouseArtStore.fileName(for: HouseRoomArtKey(rawValue: "a/b")))
        XCTAssertNil(HouseArtStore.fileName(for: HouseRoomArtKey(rawValue: "")))
        XCTAssertNil(HouseArtStore.fileName(for: HouseRoomArtKey(rawValue: "Room")))
    }

    func testCatalogNamesFollowTheAssetScript() {
        XCTAssertEqual(HouseArtStore.catalogName(for: .gesher, variant: .card), "House/RoomCards/room-gesher-card")
        XCTAssertEqual(HouseArtStore.catalogName(for: .gesher, variant: .header), "House/Rooms/room-gesher")
        // Every key the app can produce has both images in the catalog folder the script writes.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/HarnessgramHouse.xcassets")
        guard FileManager.default.fileExists(atPath: root.path) else {
            return
        }
        for key in [HouseRoomArtKey.gesher, .projectA, .projectB, .projectC, .newRoom] {
            for variant in [HouseArtVariant.card, .header] {
                let name = HouseArtStore.catalogName(for: key, variant: variant)
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name + ".imageset/Contents.json").path), name)
            }
        }
    }

    func testAReplacementWinsOverTheDefaultAndGoesBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HouseArtStore(directory: directory, bundle: Bundle(for: Anchor.self))
        XCTAssertNil(store.image(for: .gesher), "no catalog art in the test bundle")
        UIGraphicsBeginImageContext(CGSize(width: 4.0, height: 4.0))
        UIColor.red.setFill()
        UIRectFill(CGRect(x: 0.0, y: 0.0, width: 4.0, height: 4.0))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        let png = try XCTUnwrap(image?.pngData())
        XCTAssertTrue(store.setReplacement(png, for: .gesher))
        XCTAssertNotNil(store.image(for: .gesher))
        XCTAssertFalse(store.setReplacement(Data("not an image".utf8), for: .projectB))
        store.removeReplacement(for: .gesher)
        XCTAssertNil(store.image(for: .gesher))
    }
}
