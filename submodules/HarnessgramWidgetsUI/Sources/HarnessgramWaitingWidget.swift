import Foundation
import SwiftUI
import WidgetKit
import HarnessgramCockpitKit

public struct HarnessgramWaitingEntry: TimelineEntry {
    public let date: Date
    /// nil before the app ever reached the Cockpit.
    public let snapshot: HarnessgramCockpitSnapshot?
    /// The stored login can still answer: plain decisions get in-place buttons.
    public let canAnswerOnWidget: Bool
    /// No Cockpit login was ever saved for the current account: the widget is not paired with the bridge yet.
    public let needsPairing: Bool
    /// The shared store was busy (the app held its lock): no account data, no answer buttons, not the pairing view.
    public let temporarilyUnavailable: Bool
    public let isSample: Bool

    public init(date: Date, snapshot: HarnessgramCockpitSnapshot?, canAnswerOnWidget: Bool, needsPairing: Bool = false, temporarilyUnavailable: Bool = false, isSample: Bool = false) {
        self.date = date
        self.snapshot = snapshot
        self.canAnswerOnWidget = canAnswerOnWidget
        self.needsPairing = needsPairing
        self.temporarilyUnavailable = temporarilyUnavailable
        self.isSample = isSample
    }

    public static func unavailable(at date: Date) -> HarnessgramWaitingEntry {
        return HarnessgramWaitingEntry(date: date, snapshot: nil, canAnswerOnWidget: false, needsPairing: false, temporarilyUnavailable: true)
    }

    public static let preview = HarnessgramWaitingEntry(date: HarnessgramCockpitSnapshot.sample.updatedAt.addingTimeInterval(120), snapshot: .sample, canAnswerOnWidget: true)

    static func sampleEntry(now: Date) -> HarnessgramWaitingEntry? {
        guard let snapshot = HarnessgramSampleStore.shared?.read()?.snapshot else { return nil }
        return HarnessgramWaitingEntry(date: now, snapshot: snapshot, canAnswerOnWidget: false, isSample: true)
    }
}

@available(iOS 17.0, *)
struct HarnessgramWaitingProvider: TimelineProvider {
    static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> HarnessgramWaitingEntry {
        return .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (HarnessgramWaitingEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
            return
        }
        let now = Date()
        completion(HarnessgramWaitingEntry.sampleEntry(now: now) ?? HarnessgramWaitingProvider.snapshotEntry(store: .shared, now: now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HarnessgramWaitingEntry>) -> Void) {
        Task {
            let now = Date()
            if let sample = HarnessgramWaitingEntry.sampleEntry(now: now) {
                completion(Timeline(entries: [sample], policy: .after(now.addingTimeInterval(Self.refreshInterval))))
            } else {
                completion(await HarnessgramWaitingProvider.timeline(store: .shared, client: HarnessgramCockpitClient(), now: now))
            }
        }
    }

    /// The widget refreshes by itself while the app's last Cockpit login can still read (about an hour);
    /// after that it shows the last snapshot until the app is opened. A second entry drops the in-place
    /// buttons the moment the login stops being able to answer.
    /// The widget's quick snapshot (build 16): one atomic read of session, snapshot and login, and nothing shown when
    /// the session changed by the time the entry is made.
    static func snapshotEntry(store: HarnessgramCockpitStore, now: Date) -> HarnessgramWaitingEntry {
        // A lock held by the app is not "logged out": a few short tries, then a neutral entry (never the pairing one).
        var lookup = store.answerContextChecked()
        for _ in 0 ..< 3 {
            guard case .lockUnavailable = lookup else { break }
            usleep(30_000)
            lookup = store.answerContextChecked()
        }
        // Anything unknown (a busy lock) gives the neutral unavailable entry, never a snapshot or the pairing view.
        guard case let .completed(context) = lookup else {
            return .unavailable(at: now)
        }
        if let context {
            guard case let .completed(current) = store.sessionChecked() else {
                return .unavailable(at: now)
            }
            if current == context.session {
                return HarnessgramWaitingEntry(date: now, snapshot: context.snapshot, canAnswerOnWidget: context.credential?.canAnswer(now: now) ?? false, needsPairing: false)
            }
        }
        guard case let .completed(hasLogin) = store.hasLoginChecked() else {
            return .unavailable(at: now)
        }
        return HarnessgramWaitingEntry(date: now, snapshot: nil, canAnswerOnWidget: false, needsPairing: !hasLogin)
    }

    /// How soon the widget asks again when the shared store was busy (the app held its lock).
    static let lockRetryInterval: TimeInterval = 60

    /// The store was busy: exactly one neutral entry (no account data, no buttons, not the pairing view) and a new
    /// timeline within a minute. (An empty timeline has nothing to keep on a first load.)
    static func unavailableTimeline(now: Date) -> Timeline<HarnessgramWaitingEntry> {
        return Timeline(entries: [.unavailable(at: now)], policy: .after(now.addingTimeInterval(lockRetryInterval)))
    }

    static func timeline(store: HarnessgramCockpitStore, client: HarnessgramCockpitClient, now: Date) async -> Timeline<HarnessgramWaitingEntry> {
        // A lock timeout is never read as "logged out", "no snapshot" or "not paired": it gives the unavailable entry.
        // The session is captured first; a refresh that ends in another session (switch or logout) shows nothing of it.
        guard case let .completed(context) = await HarnessgramCockpitStore.retrying({ store.answerContextChecked() }) else {
            return unavailableTimeline(now: now)
        }
        let session: HarnessgramCockpitStore.Session?
        if let context {
            session = context.session
        } else {
            guard case let .completed(current) = await HarnessgramCockpitStore.retrying({ store.sessionChecked() }) else {
                return unavailableTimeline(now: now)
            }
            session = current
        }
        var snapshot = context?.snapshot
        var credential = context?.credential ?? (session == nil ? nil : store.loadCredential(forSession: session))
        if let session, let readable = credential, readable.canRead(now: now) {
            do {
                let fresh = try await client.fetchSnapshot(credential: readable, now: now)
                // Saved only while the same session is current; answered decisions stay out (the store filters). The
                // stored copy comes back from the same locked step; a busy store keeps the snapshot read above.
                if case let .completed(stored?) = await HarnessgramCockpitStore.retrying({ store.storeSnapshot(fresh, openDecisions: nil, forSession: session) }) {
                    snapshot = stored
                }
            } catch HarnessgramCockpitClient.FetchError.expired {
                store.forgetCredential(forSession: session)
            } catch {
            }
        }
        guard case let .completed(current) = await HarnessgramCockpitStore.retrying({ store.sessionChecked() }) else {
            return unavailableTimeline(now: now)
        }
        if current != session {
            // Switched or logged out meanwhile: drop everything read in the old session.
            snapshot = nil
            credential = nil
        }
        var needsPairing = false
        if snapshot == nil {
            guard case let .completed(hasLogin) = await HarnessgramCockpitStore.retrying({ store.hasLoginChecked() }) else {
                return unavailableTimeline(now: now)
            }
            needsPairing = !hasLogin
        }
        var entries = [HarnessgramWaitingEntry(date: now, snapshot: snapshot, canAnswerOnWidget: credential?.canAnswer(now: now) ?? false, needsPairing: needsPairing)]
        if let credential, credential.canAnswer(now: now) {
            let closes = credential.authDate.addingTimeInterval(HarnessgramCockpitCredential.answerWindow)
            if closes > now {
                entries.append(HarnessgramWaitingEntry(date: closes, snapshot: snapshot, canAnswerOnWidget: false, needsPairing: needsPairing))
            }
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshInterval)))
    }
}

/// "ממתין לך": the decisions waiting for the owner (count and the top lines, with Approve / Decline),
/// the agents at work and the radio. Home screen (small, medium, large) and lock screen (inline,
/// circular, rectangular).
/// Widget kinds, outside the (main actor) Widget types so the button intent can name them.
public enum HarnessgramWidgetKind {
    public static let waiting = "HarnessgramWaiting"
}

@available(iOS 17.0, *)
public struct HarnessgramWaitingWidget: Widget {
    public static let kind = HarnessgramWidgetKind.waiting

    public init() {
    }

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: HarnessgramWaitingWidget.kind, provider: HarnessgramWaitingProvider()) { entry in
            HarnessgramWaitingEntryView(entry: entry)
        }
        .configurationDisplayName(HarnessgramWidgetStrings.waitingGalleryName)
        .description(HarnessgramWidgetStrings.waitingGalleryDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

@available(iOS 17.0, *)
struct HarnessgramWaitingEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HarnessgramWaitingEntry

    var body: some View {
        HarnessgramWaitingContent(entry: self.entry, family: self.family)
    }
}
