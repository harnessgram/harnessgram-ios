import Foundation

/// The sample has no bridge session, credentials, or account manager. Its one shared document is also the
/// widget and Shortcut read boundary. The app is the sole writer and replaces the document atomically.
public struct HarnessgramSampleStore: Sendable {
    public static let openURL = URL(string: "harnessgram://widget/sample")!
    public static let activityIDPrefix = "harnessgram-offline-sample-"
    public static let shared = HarnessgramCockpitStore.appGroupDirectory().map {
        HarnessgramSampleStore(container: $0.deletingLastPathComponent())
    }

    public struct State: Codable, Sendable {
        public var snapshot: HarnessgramCockpitSnapshot
        public var disabledFilterRules: Set<String>
        public private(set) var answers: [String: String]

        fileprivate init(snapshot: HarnessgramCockpitSnapshot) {
            self.snapshot = snapshot
            self.disabledFilterRules = []
            self.answers = [:]
        }

        public enum AnswerResult: Equatable {
            case applied
            case refused
            case closed
        }

        public mutating func answer(_ id: String, choice: HarnessgramCockpitLinks.Choice) -> AnswerResult {
            guard let decision = self.snapshot.decisions.first(where: { $0.id == id }) else { return .closed }
            guard !decision.sensitive else { return .refused }
            self.snapshot.decisions.removeAll { $0.id == id }
            self.answers[id] = choice.rawValue
            Self.updateWaiting(in: &self.snapshot, done: 4 + self.answers.count)
            return .applied
        }

        fileprivate static func updateWaiting(in snapshot: inout HarnessgramCockpitSnapshot, done: Int) {
            snapshot.waitingCount = snapshot.decisions.count
            snapshot.today = .init(doneToday: done, totalToday: done + snapshot.waitingCount, waiting: snapshot.decisions.prefix(HarnessgramCockpitSnapshot.Today.maxWaiting).map {
                .init(title: $0.sensitive ? HarnessgramWidgetStrings.needsFaceID : $0.title, ageMinutes: 5, url: HarnessgramSampleStore.openURL)
            })
        }
    }

    public let directory: URL

    public init(container: URL) {
        self.directory = container.appendingPathComponent("harnessgram-offline-sample", isDirectory: true)
    }

    private var document: URL { self.directory.appendingPathComponent("sample.json") }
    private var realAccountMarker: URL {
        self.directory.deletingLastPathComponent().appendingPathComponent("harnessgram-sample-suppressed")
    }

    public func read(cockpitStore: HarnessgramCockpitStore = .shared) -> State? {
        guard let data = try? Data(contentsOf: self.document) else { return nil }
        guard case .completed(nil) = cockpitStore.sessionChecked() else { return nil }
        do {
            _ = try FileManager.default.attributesOfItem(atPath: self.realAccountMarker.path)
            return nil
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // No real account has superseded this sample.
        } catch {
            return nil
        }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    /// Kept outside the sample directory so a failed erase cannot hide a real sign-in, even with Cockpit paused.
    public func markRealAccountActive() throws {
        try Data().write(to: self.realAccountMarker, options: .atomic)
    }

    public func prepare() throws {
        try self.erase()
        // Only an explicit new sample can clear the marker, after the previous sample has been removed.
        try self.removeIfPresent(self.realAccountMarker)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: false)
    }

    public func write(_ state: State) throws {
        try JSONEncoder().encode(state).write(to: self.document, options: .atomic)
    }

    public func erase() throws {
        try self.removeIfPresent(self.directory)
    }

    private func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // Already removed.
        }
    }

    public static func initialState(now: Date = Date()) -> State {
        var snapshot = HarnessgramCockpitSnapshot.houseDemo
        snapshot.updatedAt = now
        // The screenshot fixtures have Telegram topic addresses. The on-device sample routes entirely inside the app.
        snapshot.agents = snapshot.agents.map { agent in
            var agent = agent
            agent.topicURL = ""
            return agent
        }
        snapshot.progress = snapshot.progress.prefix(HarnessgramCockpitSnapshot.maxProgress).map { progress in
            var progress = progress
            progress.topicURL = ""
            return progress
        }
        snapshot.decisions = HarnessgramSampleDecisionStrings.decisions(now: now)
        State.updateWaiting(in: &snapshot, done: 4)
        return State(snapshot: snapshot)
    }
}
