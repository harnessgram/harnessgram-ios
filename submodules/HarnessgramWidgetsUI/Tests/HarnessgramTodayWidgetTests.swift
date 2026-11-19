import Foundation
import SwiftUI
import WidgetKit
import XCTest
import HarnessgramCockpitKit
@testable import HarnessgramWidgetsUI

@available(iOS 17.0, *)
final class HarnessgramTodayWidgetTests: XCTestCase {
    private let url = URL(string: "https://t.me/example?startapp=r1")!

    func testFormatsCountsAndAgesAndKeepsRowDestinations() {
        let secondURL = URL(string: "https://t.me/example?startapp=r2")!
        let thirdURL = URL(string: "https://t.me/example?startapp=r3")!
        let today = HarnessgramCockpitSnapshot.Today(doneToday: 4, totalToday: 8, waiting: [
            .init(title: "First", ageMinutes: 12, url: self.url),
            .init(title: "Second", ageMinutes: 59, url: secondURL),
            .init(title: "Third", ageMinutes: 185, url: thirdURL),
            .init(title: "Fourth", ageMinutes: 240, url: self.url),
        ])
        let model = HarnessgramTodayViewModel(today: today, strings: .english)
        XCTAssertEqual(model.progress, "4 of 8 done today")
        XCTAssertEqual(model.fractionDone, 0.5)
        XCTAssertEqual(model.rows.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(model.rows.map(\.age), ["12 min", "59 min", "3 h"])
        XCTAssertEqual(model.rows.map(\.url), [self.url, secondURL, thirdURL])
        XCTAssertEqual(model.strings.age(minutes: 60), "1 h")
        XCTAssertEqual(model.strings.age(minutes: 0), "0 min")
        XCTAssertEqual(model.strings.age(minutes: 48 * 60 - 1), "47 h")
        XCTAssertEqual(model.strings.age(minutes: 48 * 60), "2 d")
        XCTAssertEqual(model.strings.age(minutes: Int.max), "99 d")
    }

    func testLanguageSelectionUsesPreferencesWithoutAnExplicitLocale() {
        typealias TodayStrings = HarnessgramWidgetStrings.Today
        XCTAssertEqual(TodayStrings(), TodayStrings(preferredLanguages: Locale.preferredLanguages))
        XCTAssertEqual(TodayStrings(preferredLanguages: ["he-IL", "en-US"]), .hebrew)
        XCTAssertEqual(TodayStrings(preferredLanguages: ["en-US", "he-IL"]), .english)
        XCTAssertEqual(TodayStrings(preferredLanguages: ["fr-FR"]), .hebrew)
        XCTAssertEqual(TodayStrings(preferredLanguages: []), .hebrew)
    }

    func testHebrewStringsAndLayoutDirection() {
        let hebrew = HarnessgramWidgetStrings.Today.hebrew
        let english = HarnessgramWidgetStrings.Today.english
        XCTAssertTrue(hebrew.isRightToLeft)
        XCTAssertFalse(english.isRightToLeft)
        XCTAssertEqual(hebrew.title, "היום")
        XCTAssertEqual(hebrew.galleryName, "הרנסגרם: היום")
        XCTAssertEqual(english.title, "Today")
        XCTAssertEqual(hebrew.progress(done: 2, total: 9), "הושלמו היום 2 מתוך 9")
        XCTAssertEqual(hebrew.age(minutes: 12), "12 דק׳")
        XCTAssertEqual(hebrew.age(minutes: 180), "3 ש׳")
        XCTAssertEqual(hebrew.age(minutes: 48 * 60), "2 ימים")
        let empty = HarnessgramTodayViewModel(today: .empty, strings: hebrew)
        XCTAssertEqual(empty.emptyText, "אין משימות להיום")
        XCTAssertEqual(empty.fractionDone, 0)
        XCTAssertTrue(empty.rows.isEmpty)
        let done = HarnessgramTodayViewModel(today: .init(doneToday: 2, totalToday: 2, waiting: []), strings: hebrew)
        XCTAssertEqual(done.emptyText, "אין משימות שמחכות לך")
        XCTAssertEqual(done.fractionDone, 1)
    }

    @MainActor
    func testTapTargetsAndVisibleRowsByFamily() {
        let otherURL = URL(string: "https://t.me/example?startapp=other")!
        let model = HarnessgramTodayViewModel(today: .init(doneToday: 0, totalToday: 0, waiting: [
            .init(title: "First", ageMinutes: 12, url: self.url),
            .init(title: "Second", ageMinutes: 58, url: otherURL),
            .init(title: "Third", ageMinutes: 180, url: otherURL),
        ]), strings: .hebrew)
        let small = HarnessgramTodayContent(model: model, family: .systemSmall)
        let medium = HarnessgramTodayContent(model: model, family: .systemMedium)
        let lockScreen = HarnessgramTodayContent(model: model, family: .accessoryRectangular)
        XCTAssertEqual(small.tapURL, self.url)
        XCTAssertEqual(medium.tapURL, HarnessgramCockpitLinks.openURL)
        XCTAssertEqual(lockScreen.tapURL, self.url)
        XCTAssertEqual(lockScreen.visibleRows.map(\.title), ["First", "Second"])
        XCTAssertEqual(small.visibleRows.count, 3)
        XCTAssertEqual(medium.visibleRows.count, 3)

        let oldURL = URL(string: "https://other.example.test/one")!
        let cached = HarnessgramTodayViewModel(today: .init(doneToday: 0, totalToday: 0, waiting: [
            .init(title: "Cached unsupported link", ageMinutes: 12, url: oldURL),
        ]), strings: .hebrew)
        XCTAssertTrue(cached.rows.isEmpty)
        for family in [WidgetFamily.systemSmall, .accessoryRectangular] {
            XCTAssertEqual(HarnessgramTodayContent(model: cached, family: family).tapURL, HarnessgramCockpitLinks.cockpitURL)
        }
    }

    /// The notification extension reloads exactly the widgets this module declares.
    func testReloadThrottleNamesTheRealWidgetKinds() {
        XCTAssertEqual(HarnessgramWidgetReloadThrottle.bridgeWidgetKinds, [HarnessgramTodayWidget.kind, HarnessgramWidgetKind.waiting])
    }

    /// An unpaired widget asks to connect (never "no tasks today") and every family's tap opens the pairing link.
    @MainActor
    func testUnpairedWidgetAsksToConnectAndTapsPair() {
        let unpaired = HarnessgramTodayViewModel(today: .empty, strings: .hebrew, needsPairing: true)
        XCTAssertEqual(unpaired.emptyText, HarnessgramWidgetStrings.needsPairing)
        XCTAssertNotEqual(unpaired.emptyText, HarnessgramWidgetStrings.Today.hebrew.empty)
        for family in [WidgetFamily.systemSmall, .systemMedium, .accessoryRectangular] {
            XCTAssertEqual(HarnessgramTodayContent(model: unpaired, family: family).tapURL, HarnessgramCockpitLinks.pairURL, "\(family)")
        }
        let paired = HarnessgramTodayViewModel(today: .empty, strings: .hebrew, needsPairing: false)
        XCTAssertEqual(paired.emptyText, "אין משימות להיום")
        XCTAssertEqual(HarnessgramTodayContent(model: paired, family: .systemSmall).tapURL, HarnessgramCockpitLinks.cockpitURL)
    }

    @MainActor
    func testSupportedFamiliesRenderWithFullAndAccentedColors() {
        let today = HarnessgramCockpitSnapshot.Today(doneToday: 2, totalToday: 5, waiting: [
            .init(title: "משימה ראשונה", ageMinutes: 12, url: self.url),
            .init(title: "משימה שנייה", ageMinutes: 58, url: self.url),
            .init(title: "משימה שלישית", ageMinutes: 180, url: self.url),
        ])
        let families: [(WidgetFamily, CGSize)] = [
            (.systemSmall, CGSize(width: 155, height: 155)),
            (.systemMedium, CGSize(width: 329, height: 155)),
            (.accessoryRectangular, CGSize(width: 172, height: 76)),
        ]
        for (family, size) in families {
            for mode in [WidgetRenderingMode.fullColor, .accented, .vibrant] {
                let model = HarnessgramTodayViewModel(today: today, strings: .hebrew)
                let view = HarnessgramTodayContent(model: model, family: family)
                    .frame(width: size.width, height: size.height)
                    .environment(\.widgetRenderingMode, mode)
                XCTAssertNotNil(ImageRenderer(content: view).uiImage, "\(family), \(mode)")
            }
        }
    }
}
