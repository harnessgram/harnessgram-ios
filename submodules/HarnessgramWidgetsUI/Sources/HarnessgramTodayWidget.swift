import Foundation
import SwiftUI
import WidgetKit
import HarnessgramCockpitKit

@available(iOS 17.0, *)
public struct HarnessgramTodayWidget: Widget {
    public static let kind = "HarnessgramToday"

    public init() {
    }

    public var body: some WidgetConfiguration {
        let strings = HarnessgramWidgetStrings.Today()
        return StaticConfiguration(kind: Self.kind, provider: HarnessgramTodayProvider()) { entry in
            HarnessgramTodayEntryView(entry: entry)
        }
        .configurationDisplayName(strings.galleryName)
        .description(strings.galleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
        .containerBackgroundRemovable(true)
    }
}

private struct HarnessgramTodayEntry: TimelineEntry {
    let date: Date
    let today: HarnessgramCockpitSnapshot.Today
    let bridgeOrigin: URL?
    var needsPairing: Bool = false

    static let preview = HarnessgramTodayEntry(date: HarnessgramCockpitSnapshot.sample.updatedAt, today: .init(
        doneToday: 4,
        totalToday: 7,
        waiting: [
            .init(title: "לאשר את תדריך הבוקר", ageMinutes: 12, url: URL(string: "https://t.me/example?startapp=sample1")!),
            .init(title: "לבחור עיצוב למסך הבית", ageMinutes: 36, url: URL(string: "https://t.me/example?startapp=sample2")!),
            .init(title: "לבדוק את תוכנית הטיסה", ageMinutes: 180, url: URL(string: "https://t.me/example?startapp=sample3")!),
        ]
    ), bridgeOrigin: nil)
}

@available(iOS 17.0, *)
private struct HarnessgramTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> HarnessgramTodayEntry {
        return .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (HarnessgramTodayEntry) -> Void) {
        completion(context.isPreview ? .preview : self.readSnapshot())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HarnessgramTodayEntry>) -> Void) {
        Task {
            // The same bounded refresh as "ממתין לך" (one read of the bridge while the app's login can still read, saved
            // only in the same session), so a reload asked by a bridge notification shows fresh numbers, not the copy
            // the app saved last time it was open.
            let waiting = await HarnessgramWaitingProvider.timeline(store: .shared, client: HarnessgramCockpitClient(), now: Date())
            let needsPairing = waiting.entries.first?.needsPairing ?? false
            var entry = self.readSnapshot()
            entry.needsPairing = needsPairing
            completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60))))
        }
    }

    private func readSnapshot() -> HarnessgramTodayEntry {
        let context = HarnessgramCockpitStore.shared.answerContext()
        return HarnessgramTodayEntry(date: Date(), today: context?.snapshot.today ?? .empty, bridgeOrigin: context?.credential?.originURL)
    }
}

@available(iOS 17.0, *)
private struct HarnessgramTodayEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HarnessgramTodayEntry

    var body: some View {
        let model = HarnessgramTodayViewModel(today: self.entry.today, strings: .init(), bridgeOrigin: self.entry.bridgeOrigin, needsPairing: self.entry.needsPairing)
        HarnessgramTodayContent(model: model, family: self.family)
    }
}
