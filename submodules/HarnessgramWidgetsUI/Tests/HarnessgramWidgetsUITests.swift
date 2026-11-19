import XCTest
import SwiftUI
import WidgetKit
import UIKit
import HarnessgramCockpitKit
import HarnessgramSettings
@testable import HarnessgramWidgetsUI

/// Renders every widget family and the Live Activity banner. PNGs are written only when
/// /private/tmp/harnessgram-widget-snapshots exists (opt-in), for the visual check.
final class HarnessgramWidgetsUITests: XCTestCase {
    private static let snapshotFolder = URL(fileURLWithPath: "/private/tmp/harnessgram-widget-snapshots", isDirectory: true)

    private let sizes: [(WidgetFamily, CGSize, String)] = [
        (.systemSmall, CGSize(width: 170, height: 170), "small"),
        (.systemMedium, CGSize(width: 364, height: 170), "medium"),
        (.systemLarge, CGSize(width: 364, height: 382), "large"),
        (.accessoryRectangular, CGSize(width: 172, height: 76), "lock-rectangular"),
        (.accessoryCircular, CGSize(width: 76, height: 76), "lock-circular"),
        (.accessoryInline, CGSize(width: 260, height: 26), "lock-inline"),
    ]

    @MainActor
    private func render<V: View>(_ view: V, size: CGSize, dark: Bool = false) -> UIImage? {
        let framed = view
            .frame(width: size.width, height: size.height)
            .background(Color(.systemBackground))
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 3
        return renderer.uiImage
    }

    private func save(_ image: UIImage, name: String) {
        guard FileManager.default.fileExists(atPath: HarnessgramWidgetsUITests.snapshotFolder.path), let data = image.pngData() else {
            return
        }
        try? data.write(to: HarnessgramWidgetsUITests.snapshotFolder.appendingPathComponent(name + ".png"))
    }

    @MainActor
    func testEveryFamilyRendersWithSampleData() {
        for (family, size, name) in self.sizes {
            for dark in [false, true] {
                let image = self.render(HarnessgramWaitingContent(entry: .preview, family: family), size: size, dark: dark)
                XCTAssertNotNil(image, name)
                if let image {
                    XCTAssertEqual(image.size.width, size.width, accuracy: 0.5, name)
                    self.save(image, name: "waiting-\(name)\(dark ? "-dark" : "")")
                }
            }
        }
    }

    /// Build 30 (owner's tinted lock screen): the approve button was a blank white pill. Only the full-colour look keeps
    /// the white label on a fill; the tinted, Clear and lock-screen looks draw it in one tone with a border.
    func testTheApproveButtonIsNeverWhiteOnAFillOutsideFullColour() {
        XCTAssertEqual(HarnessgramAnswerLabel.style(filled: true, renderingMode: .fullColor), .solid)
        XCTAssertEqual(HarnessgramAnswerLabel.style(filled: true, renderingMode: .accented), .tinted)
        XCTAssertEqual(HarnessgramAnswerLabel.style(filled: true, renderingMode: .vibrant), .tinted)
        for mode in [WidgetRenderingMode.fullColor, .accented, .vibrant] {
            XCTAssertEqual(HarnessgramAnswerLabel.style(filled: false, renderingMode: mode), .outline)
        }
    }

    /// The answer buttons alone in each mode, without any emulation (for the mock and to see the mode's own drawing).
    @MainActor
    func testAnswerButtonsRenderInEveryMode() {
        let folder = HarnessgramWidgetsUITests.snapshotFolder.appendingPathComponent("modes", isDirectory: true)
        for (mode, name) in [(WidgetRenderingMode.fullColor, "full-colour"), (.accented, "accented"), (.vibrant, "vibrant")] {
            let row = HStack(spacing: 6) {
                HarnessgramAnswerLabel(text: "כן", color: HarnessgramWidgetPalette.approve, filled: true)
                HarnessgramAnswerLabel(text: "לא", color: HarnessgramWidgetPalette.decline, filled: false)
            }
            .padding(8)
            .environment(\.widgetRenderingMode, mode)
            let image = self.render(row, size: CGSize(width: 140, height: 48), dark: true)
            XCTAssertNotNil(image, name)
            if let image, let data = image.pngData(), FileManager.default.fileExists(atPath: folder.path) {
                try? data.write(to: folder.appendingPathComponent("answer-buttons-\(name).png"))
            }
        }
    }

    /// An approximation of how iOS draws the one-tone looks over the wallpaper, with no container background. Good
    /// enough to see a label that vanishes.
    @MainActor
    private func renderOneTone<V: View>(_ view: V, size: CGSize, mode: WidgetRenderingMode, tone: Color, viewMode: WidgetRenderingMode? = nil) -> UIImage? {
        // viewMode: the mode the view itself is told (default: the drawn mode); a different one reproduces a view that
        // ignores the system's mode (the build 30 bug).
        let told = viewMode ?? mode
        let wallpaper = LinearGradient(colors: [Color(red: 0.20, green: 0.16, blue: 0.24), Color(red: 0.10, green: 0.08, blue: 0.13)], startPoint: .top, endPoint: .bottom)
        let framed = ZStack {
            wallpaper
            if mode == .accented {
                // Accented (tinted, Clear): iOS keeps only each pixel's coverage and paints it in one tint, so a white
                // label on a solid fill disappears (the build 30 bug); this mask does the same.
                Rectangle()
                    .fill(tone)
                    .mask(view.environment(\.widgetRenderingMode, told).environment(\.colorScheme, .dark))
            } else {
                // Vibrant (lock screen): brightness decides.
                view
                    .environment(\.widgetRenderingMode, told)
                    .environment(\.colorScheme, .dark)
                    .grayscale(1.0)
                    .colorMultiply(tone)
            }
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// Brightness (0...1) of every pixel in the middle of the image (the label's area), for the pixel checks.
    private func centreBrightness(_ image: UIImage) -> [Double] {
        guard let cg = image.cgImage else {
            return []
        }
        let width = cg.width
        let height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return []
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var out: [Double] = []
        for y in (height * 3 / 10) ..< (height * 7 / 10) {
            for x in (width * 3 / 10) ..< (width * 7 / 10) {
                let i = (y * width + x) * 4
                out.append((Double(pixels[i]) + Double(pixels[i + 1]) + Double(pixels[i + 2])) / (3.0 * 255.0))
            }
        }
        return out
    }

    /// Review of 581e34df: in the tinted render the approve label must differ from its fill (the build 30 bug was a
    /// pill of one tone). The same check on a label that ignores the mode (white on its fill) finds no label, so the
    /// check itself is known to catch the bug.
    @MainActor
    func testTheApproveLabelStandsOutFromItsFillInTheTintedRender() {
        let label = HarnessgramAnswerLabel(text: "כן", color: HarnessgramWidgetPalette.approve, filled: true)
        let size = CGSize(width: 56, height: 30)
        let tone = Color(red: 0.86, green: 0.80, blue: 0.95)
        let fixed = self.centreBrightness(XCTUnwrapImage(self.renderOneTone(label, size: size, mode: .accented, tone: tone)))
        let bug = self.centreBrightness(XCTUnwrapImage(self.renderOneTone(label, size: size, mode: .accented, tone: tone, viewMode: .fullColor)))
        XCTAssertFalse(fixed.isEmpty)
        XCTAssertGreaterThan((fixed.max() ?? 0) - (fixed.min() ?? 0), 0.3, "the tinted label blends into its fill")
        XCTAssertLessThan((bug.max() ?? 0) - (bug.min() ?? 0), 0.05, "the check no longer reproduces the build 30 pill")
    }

    /// Every family in every rendering mode (full colour light and dark, accented/tinted, vibrant/Clear), written to
    /// /private/tmp/harnessgram-widget-snapshots/modes when that folder exists: the owner's mock before a build.
    @MainActor
    func testEveryFamilyRendersInEveryRenderingMode() {
        let folder = HarnessgramWidgetsUITests.snapshotFolder.appendingPathComponent("modes", isDirectory: true)
        if FileManager.default.fileExists(atPath: HarnessgramWidgetsUITests.snapshotFolder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for (family, size, name) in self.sizes {
            let view = HarnessgramWaitingContent(entry: .preview, family: family)
            var images: [(String, UIImage?)] = []
            for dark in [false, true] {
                images.append(("full-colour\(dark ? "-dark" : "")", self.render(view.environment(\.widgetRenderingMode, .fullColor), size: size, dark: dark)))
            }
            images.append(("tinted", self.renderOneTone(view, size: size, mode: .accented, tone: Color(red: 0.86, green: 0.80, blue: 0.95))))
            images.append(("clear-vibrant", self.renderOneTone(view, size: size, mode: .vibrant, tone: .white)))
            for (mode, image) in images {
                XCTAssertNotNil(image, "\(name) \(mode)")
                if let image, let data = image.pngData(), FileManager.default.fileExists(atPath: folder.path) {
                    try? data.write(to: folder.appendingPathComponent("waiting-\(name)-\(mode).png"))
                }
            }
        }
    }

    @MainActor
    func testEmptyAndNeverSyncedStatesRender() {
        let empty = HarnessgramCockpitSnapshot(updatedAt: Date(), waitingCount: 0, decisions: [], runningAgents: 0, agents: [], radio: nil, progress: [])
        let cases: [(HarnessgramWaitingEntry, String)] = [
            (HarnessgramWaitingEntry(date: Date(), snapshot: empty, canAnswerOnWidget: false), "empty"),
            (HarnessgramWaitingEntry(date: Date(), snapshot: nil, canAnswerOnWidget: false), "never-synced"),
            (HarnessgramWaitingEntry(date: Date(), snapshot: HarnessgramCockpitSnapshot.sample.withNotice(HarnessgramWidgetStrings.answerNotSent), canAnswerOnWidget: false), "stale-login"),
        ]
        for (entry, name) in cases {
            let image = self.render(HarnessgramWaitingContent(entry: entry, family: .systemMedium), size: CGSize(width: 364, height: 170))
            XCTAssertNotNil(image, name)
            if let image {
                self.save(image, name: "waiting-medium-\(name)")
            }
            // The lock screen pack's accessories in the same states.
            for (family, size, familyName) in self.sizes where family == .accessoryRectangular || family == .accessoryCircular || family == .accessoryInline {
                let accessory = self.render(HarnessgramWaitingContent(entry: entry, family: family), size: size, dark: true)
                XCTAssertNotNil(accessory, "\(name) \(familyName)")
                if let accessory {
                    self.save(accessory, name: "waiting-\(familyName)-\(name)")
                }
            }
        }
    }

    /// The overflow summary as choose() builds it: six hidden cards, with or without decisions waiting.
    static func summaryWithRows(waiting: Bool) -> HarnessgramTaskState {
        let t = Date().timeIntervalSince1970
        let titles: [(String, String, Int?)] = [("בניית גרסה 16", "גשר", 55), ("תיקון מסך ההתחברות", "Wings", 76), ("סרטון הסיכום השבועי", "תוכן לדוגמה", 38), ("עמוד הבית החדש", "חנות לדוגמה", 10), ("סקירת אבטחה", "פרויקט לדוגמה", nil), ("ניקוי לוגים ישנים", "גשר", 90), ("תרגום מסכי ההגדרות", "גשר", 20), ("מעבר לשרת חדש", "פרויקט לדוגמה", 64)]
        let cards = titles.enumerated().map { index, item in
            HarnessgramCockpitSnapshot.Progress(id: "c\(index)", title: item.0, topic: item.1, steps: ["קוד", "בדיקות"], done: 1, percent: item.2, topicURL: "", finished: false, updated: t - Double(index) * 60)
        }
        let plan = HarnessgramTaskActivityPlan.choose(cards, waiting: waiting ? HarnessgramTaskActivityPlan.Waiting(count: 2, firstTitle: "לשלוח את הסרטון לקבוצת ההורים?", firstSensitive: true) : nil)
        return plan.last!.state
    }

    @MainActor
    func testLiveActivityBannerRenders() {
        var summary = HarnessgramTaskState(title: HarnessgramWidgetStrings.moreTasks(4), topic: "", steps: [], done: 0, percent: nil, finished: false)
        summary.overflowCount = 4
        let states = [
            ("summary-rows", Self.summaryWithRows(waiting: true)),
            ("summary-rows-tasks", Self.summaryWithRows(waiting: false)),
            ("running", HarnessgramTaskState(title: "הסבב הבא של כלים לעוזר", topic: "מנדין", steps: ["קוד", "סקירה", "בנייה", "בדיקות", "העלאה"], done: 3, percent: 72, finished: false)),
            ("english-topic", HarnessgramTaskState(title: "בניית גרסה 13", topic: "Native lock screen widgets pack", steps: ["קוד", "בדיקות", "בנייה", "העלאה"], done: 1, percent: nil, finished: false)),
            ("done", HarnessgramTaskState(title: "בניית גרסה 13", topic: "הרנסגרם", steps: ["קוד", "בדיקות", "בנייה", "העלאה"], done: 4, percent: 100, finished: true)),
            ("summary", summary),
        ]
        let size = CGSize(width: 364, height: 156)
        // ImageRenderer has no ActivityKit host. Supply the surface that the Lock Screen normally provides.
        for (name, state) in states {
            for (scheme, dark, reduced, surface) in [
                ("light", false, false, Color.white),
                ("dark", true, false, Color.black),
                ("aod", true, true, Color.black),
                ("light-surface-dark-content-context", true, false, Color.white),
            ] {
                let view = HarnessgramTaskLockScreenBanner(state: state, isStale: false)
                    .environment(\.isLuminanceReduced, reduced)
                    .frame(width: size.width, height: size.height)
                    .background(surface)
                guard let image = self.render(view, size: size, dark: dark),
                      let inside = Self.pixel(image, x: 4, y: Int(size.height / 2)) else {
                    XCTFail("\(name) \(scheme)")
                    continue
                }
                // A stale dark content environment must never paint over a light ActivityKit surface.
                let expectedLuminance = surface == Color.white ? 1.0 : 0.0
                XCTAssertEqual(inside.relativeLuminance, expectedLuminance, accuracy: 0.01, "\(name) \(scheme)")
                if scheme != "light-surface-dark-content-context" {
                    self.save(image, name: "live-activity-\(name)-\(scheme)")
                }
            }
        }
    }

    @MainActor
    func testLiveActivityForegroundKeepsAAOnTheSystemSurfaces() throws {
        for (dark, reduced) in [(false, false), (true, false), (true, true)] {
            let colors = HarnessgramTaskActivityColors.lockScreen(luminanceReduced: reduced)
            let surface = HarnessgramRGB(hex: dark ? 0x000000 : 0xFFFFFF)
            let roles = [colors.primaryText, colors.secondaryText, colors.taskMark(finished: false), colors.taskMark(finished: true), colors.waitingMark]
            for foreground in roles {
                let swatch = Rectangle().fill(foreground).background(Color(surface))
                let image = try XCTUnwrap(self.render(swatch, size: CGSize(width: 12, height: 12), dark: dark))
                let pixel = try XCTUnwrap(Self.pixel(image, x: 6, y: 6))
                XCTAssertGreaterThanOrEqual(HarnessgramRGB.contrastRatio(pixel, surface), 4.5)
            }
        }
    }

    func testDistinctSessionsKeepTheirOwnActivities() {
        let now = Date(timeIntervalSince1970: 1_763_300_000)
        let updated = now.timeIntervalSince1970
        let cards = [
            HarnessgramCockpitSnapshot.Progress(id: "first", title: "בדיקות", topic: "Harnessgram", steps: [], done: 0, percent: 10, topicURL: "", finished: false, updated: updated),
            HarnessgramCockpitSnapshot.Progress(id: "second", title: "סקירה", topic: "Harnessgram", steps: [], done: 0, percent: 25, topicURL: "", finished: false, updated: updated - 1),
        ]
        let plan = HarnessgramTaskActivityPlan.choose(cards, now: now)
        XCTAssertEqual(plan.map(\.cardId), ["first", "second"])
        // The controller looks up an active ActivityKit record by card ID before applying this rule.
        let actions = plan.map { item in
            let existing = item.cardId == "first"
            return HarnessgramLiveActivityTokenRule.loopAction(cardId: item.cardId, live: existing, liveHasToken: existing, markedForReplace: false, appActive: true)
        }
        XCTAssertEqual(actions, [.update, .request])
    }

    /// The lock screen card's natural height stays inside the 160 pt banner iOS allows, in every state.
    @MainActor
    func testTheCardFitsTheLockScreenBanner() {
        var summary = HarnessgramTaskState(title: HarnessgramWidgetStrings.moreTasks(2), topic: "", steps: [], done: 0, percent: nil, finished: false)
        summary.overflowCount = 2
        let states = [
            Self.summaryWithRows(waiting: true),
            Self.summaryWithRows(waiting: false),
            HarnessgramTaskState(title: "הסבב הבא של כלים לעוזר", topic: "מנדין", steps: ["קוד", "בדיקות"], done: 1, percent: 72, finished: false),
            HarnessgramTaskState(title: "בניית גרסה", topic: "Native lock screen widgets pack", steps: ["קוד", "בדיקות"], done: 1, percent: nil, finished: false),
            summary,
        ]
        for state in states {
            let host = UIHostingController(rootView: HarnessgramTaskLockScreenView(state: state, isStale: true))
            let size = host.sizeThatFits(in: CGSize(width: 364, height: 400))
            XCTAssertLessThanOrEqual(size.height, 160, state.title)
        }
    }

    /// The expanded Dynamic Island's bottom row and the compact dial, on the island's black.
    @MainActor
    func testIslandPartsRender() {
        let palette = HarnessgramTaskActivityPalette.standard
        let colors = HarnessgramTaskActivityColors(instruments: palette)
        let state = HarnessgramTaskState(title: "מימוש תכונת חיפוש חכם", topic: "", steps: ["קוד", "סקירה", "בנייה", "בדיקות", "העלאה"], done: 3, percent: 72, finished: false)
        let expanded = HStack(spacing: 14) {
            HarnessgramTaskTextColumn(state: state, colors: colors, titleSize: 16, showsBar: true, glows: true, showsPercent: false)
            HarnessgramAltimeterDial(fraction: state.fraction, finished: false, palette: palette)
                .frame(width: 66, height: 66)
        }
        .frame(height: 70)
        .padding(16)
        .background(Color.black)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.colorScheme, .dark)
        if let image = self.render(expanded, size: CGSize(width: 370, height: 104), dark: true) {
            self.save(image, name: "island-expanded")
        } else {
            XCTFail("expanded island")
        }
        // The overflow summary in the expanded island: the rows on the island's black.
        let summary = HarnessgramTaskSummaryBody(state: Self.summaryWithRows(waiting: true), colors: colors, rowSize: 13)
            .padding(16)
            .background(Color.black)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.colorScheme, .dark)
        if let image = self.render(summary, size: CGSize(width: 370, height: 104), dark: true) {
            self.save(image, name: "island-expanded-summary")
        } else {
            XCTFail("expanded island summary")
        }
        let compact = HStack(spacing: 40) {
            HarnessgramAltimeterDial(fraction: 0.72, finished: false, palette: palette, detailed: false).frame(width: 18, height: 18)
            Text("72%").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Color(palette.accent))
            HarnessgramTaskRing(fraction: 0.72, finished: false, palette: palette).frame(width: 22, height: 22)
        }
        .padding(8)
        .background(Capsule().fill(Color.black))
        if let image = self.render(compact, size: CGSize(width: 200, height: 40), dark: true) {
            self.save(image, name: "island-compact-minimal")
        } else {
            XCTFail("compact island")
        }
    }

    /// The small family (Apple Watch Smart Stack, CarPlay, Mac menu bar) renders on a light and a dark tile, at watch
    /// size too.
    @MainActor
    func testSmallFamilyRendersInLightAndDark() {
        var summary = HarnessgramTaskState(title: HarnessgramWidgetStrings.moreTasks(3), topic: "", steps: [], done: 0, percent: nil, finished: false)
        summary.overflowCount = 3
        let states = [
            ("running", HarnessgramTaskState(title: "בניית גרסה 22 של האפליקציה לבדיקה", topic: "הרנסגרם", steps: ["קוד", "בדיקות", "בנייה", "העלאה"], done: 2, percent: 70, finished: false)),
            ("done", HarnessgramTaskState(title: "בניית גרסה 22", topic: "הרנסגרם", steps: ["קוד", "בדיקות"], done: 2, percent: 100, finished: true)),
            ("summary", summary),
        ]
        for (name, state) in states {
            for dark in [false, true] {
                for (sizeName, size) in [("", CGSize(width: 170, height: 100)), ("-watch", CGSize(width: 162, height: 76))] {
                    let image = self.render(HarnessgramTaskSmallView(state: state), size: size, dark: dark)
                    XCTAssertNotNil(image)
                    if let image {
                        self.save(image, name: "live-activity-small-\(name)\(sizeName)-\(dark ? "dark" : "light")")
                    }
                }
            }
        }
    }

    private static func pixel(_ image: UIImage, x: Int, y: Int) -> HarnessgramRGB? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let scale = Int(image.scale)
        context.draw(cgImage, in: CGRect(x: -x * scale, y: -(cgImage.height - y * scale - 1), width: cgImage.width, height: cgImage.height))
        return HarnessgramRGB(red: Double(bytes[0]) / 255.0, green: Double(bytes[1]) / 255.0, blue: Double(bytes[2]) / 255.0)
    }

    /// Build 21: the Live Activity keeps one spacing system (16 outside, 12 between blocks, even gaps) and the compact
    /// island regions keep their content off the pill's rounded ends.
    func testTheTaskLiveActivityKeepsItsSpacingSystem() {
        XCTAssertEqual(HarnessgramTaskActivityLayout.outer, 16)
        XCTAssertTrue((12...16).contains(HarnessgramTaskActivityLayout.inner))
        XCTAssertLessThanOrEqual(HarnessgramTaskActivityLayout.gap, HarnessgramTaskActivityLayout.inner)
        XCTAssertTrue((6...8).contains(HarnessgramTaskActivityLayout.compactOuter))
        XCTAssertGreaterThan(HarnessgramTaskActivityLayout.compactInner, 0)
        XCTAssertLessThanOrEqual(HarnessgramTaskActivityLayout.compactInner, HarnessgramTaskActivityLayout.compactOuter)
        XCTAssertGreaterThan(HarnessgramTaskActivityLayout.minimalInset, 0)
        // Build 24: the expanded island's rows keep clear of its rounded corners (step line was clipped).
        XCTAssertGreaterThanOrEqual(HarnessgramTaskActivityLayout.islandCorner, HarnessgramTaskActivityLayout.inner)
    }

    func testSensitiveLinesNeverGetInPlaceButtons() {
        for decision in HarnessgramCockpitSnapshot.sample.decisions {
            for canAnswer in [false, true] {
                let route = HarnessgramWaitingContent.route(decision, canAnswerOnWidget: canAnswer)
                if decision.sensitive {
                    XCTAssertEqual(route, .answerInAppWithFaceID)
                } else {
                    XCTAssertEqual(route, canAnswer ? .answerOnWidget : .answerInApp)
                }
            }
        }
    }

    func testAnswerIntentRequiresAnUnlockedPhone() {
        XCTAssertEqual(HarnessgramAnswerIntent.authenticationPolicy, .requiresAuthentication)
        XCTAssertFalse(HarnessgramAnswerIntent.isDiscoverable)
    }

    // MARK: Build 16: the quick snapshot path

    func testTheQuickSnapshotIsOneReadOfTheCurrentSession() {
        guard #available(iOS 17.0, *) else {
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HarnessgramCockpitStore(directory: directory)
        let now = HarnessgramCockpitSnapshot.sample.updatedAt
        XCTAssertNil(HarnessgramWaitingProvider.snapshotEntry(store: store, now: now).snapshot, "logged out")
        XCTAssertTrue(HarnessgramWaitingProvider.snapshotEntry(store: store, now: now).needsPairing)
        let a = store.setActiveAccount(11)
        store.saveSnapshot(.sample, forSession: a)
        store.saveCredential(HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: now, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"])), forSession: a)
        let entry = HarnessgramWaitingProvider.snapshotEntry(store: store, now: now)
        XCTAssertEqual(entry.snapshot?.decisions.count, 3)
        XCTAssertTrue(entry.canAnswerOnWidget)
        XCTAssertFalse(entry.needsPairing)
        store.setActiveAccount(22)
        let switched = HarnessgramWaitingProvider.snapshotEntry(store: store, now: now)
        XCTAssertNil(switched.snapshot, "nothing of account 11 after the switch")
        XCTAssertFalse(switched.canAnswerOnWidget)
    }

    /// The app holding the store's lock is not "logged out": the quick entry is neutral (never the pairing one) and
    /// the timeline publishes no entry (WidgetKit keeps the last good one) and asks again soon.
    func testABusyStoreKeepsTheLastEntry() async throws {
        guard #available(iOS 17.0, *) else {
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HarnessgramCockpitStore(directory: directory)
        let now = HarnessgramCockpitSnapshot.sample.updatedAt
        let a = store.setActiveAccount(11)
        store.saveSnapshot(.sample, forSession: a)
        let fd = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        let quick = HarnessgramWaitingProvider.snapshotEntry(store: store, now: now)
        XCTAssertNil(quick.snapshot)
        XCTAssertFalse(quick.needsPairing, "busy is not unpaired")
        XCTAssertTrue(quick.temporarilyUnavailable)
        let timeline = await HarnessgramWaitingProvider.timeline(store: store, client: HarnessgramCockpitClient(), now: now)
        XCTAssertEqual(timeline.entries.count, 1, "exactly one neutral entry, even on a first load")
        XCTAssertTrue(timeline.entries[0].temporarilyUnavailable)
        XCTAssertNil(timeline.entries[0].snapshot, "no account data while unknown")
        XCTAssertFalse(timeline.entries[0].canAnswerOnWidget)
        XCTAssertFalse(timeline.entries[0].needsPairing, "not the pairing view")
        flock(fd, LOCK_UN)
        close(fd)
        let free = HarnessgramWaitingProvider.snapshotEntry(store: store, now: now)
        XCTAssertEqual(free.snapshot?.decisions.count, 3)
        XCTAssertFalse(free.temporarilyUnavailable)
    }
}

private func XCTUnwrapImage(_ image: UIImage?, file: StaticString = #filePath, line: UInt = #line) -> UIImage {
    guard let image else {
        XCTFail("no image", file: file, line: line)
        return UIImage()
    }
    return image
}
