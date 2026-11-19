import Foundation

/// Turns the bridge's Cockpit answers into a snapshot. Inputs: `POST /api/state` ("decisions", "sessions", "cards";
/// see docs/harnessgram-local-config.md) and, optionally,
/// `POST /api/radio-player` ({"enabled", "on"}). Anything unexpected is dropped, never guessed.
public enum HarnessgramCockpitParser {
    public enum ParseError: Error, Equatable {
        case notJSON
        case notOK
    }

    /// The most steps a progress card keeps (the Live Activity's step dots and the bridge's push both stop here).
    public static let maxSteps = 12

    /// The steps a card shows: all of them up to `maxSteps`; for a longer card, `maxSteps` steps that end at the
    /// current one (`at`, 0-based; `at == count` means all done): start = max(0, min(at - 11, count - 12)).
    public static func stepWindow(count: Int, at: Int) -> Range<Int> {
        let count = max(0, count)
        let at = min(max(0, at), count)
        let start = max(0, min(at - (maxSteps - 1), count - maxSteps))
        return start ..< min(count, start + maxSteps)
    }

    static let titleLimit = 140
    static let stepLimit = 100
    static let originalLimit = 1_600

    static func translated(_ item: [String: Any], sourceKey: String, hebrewKey: String, limit: Int, multiline: Bool = false) -> (display: String, source: String) {
        let source = clean(item[sourceKey], limit: originalLimit)
        let hebrew = cleanHebrew(item[hebrewKey], limit: limit, multiline: multiline)
        return (hebrew.isEmpty ? clean(source, limit: limit) : hebrew, source)
    }

    /// Hebrew keeps its bidi isolates; only the detail keeps line breaks, because titles, labels, steps and options
    /// render on one line in widgets and the Live Activity, where a second line would be cut off.
    static func cleanHebrew(_ value: Any?, limit: Int, multiline: Bool = false) -> String {
        let text = clean(value, limit: limit, preservingHebrewFormatting: true)
        if multiline {
            return text
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).joined(separator: " ")
    }

    public static func snapshot(state: Data, radioPlayer: Data?, now: Date, bridgeOrigin: URL? = nil) throws -> HarnessgramCockpitSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: state)) as? [String: Any] else {
            throw ParseError.notJSON
        }
        guard root["ok"] as? Bool == true else {
            throw ParseError.notOK
        }

        let decisions = parseDecisions(root, now: now)

        var agents: [HarnessgramCockpitSnapshot.Agent] = []
        for case let item as [String: Any] in (root["sessions"] as? [Any] ?? []) {
            guard item["state"] as? String == "working" else {
                continue
            }
            let nameText = translated(item, sourceKey: "name", hebrewKey: "name_he", limit: 60)
            let stepText = translated(item, sourceKey: "now", hebrewKey: "now_he", limit: stepLimit)
            agents.append(HarnessgramCockpitSnapshot.Agent(
                id: clean(item["id"], limit: 16),
                name: nameText.display.isEmpty ? HarnessgramWidgetStrings.unnamedAgent : nameText.display,
                step: stepText.display,
                topicURL: clean(item["url"], limit: 200),
                roomChannelId: HarnessgramCockpitLinks.channelId(fromTopicURL: clean(item["url"], limit: 200)),
                originalName: nameText.source.isEmpty ? nil : nameText.source,
                originalStep: stepText.source.isEmpty ? nil : stepText.source
            ))
        }

        var progress: [HarnessgramCockpitSnapshot.Progress] = []
        for case let item as [String: Any] in (root["cards"] as? [Any] ?? []) {
            guard item["kind"] as? String == "progress", item["ended"] as? Bool != true, item["stale"] as? Bool != true else {
                continue
            }
            let id = clean(item["id"], limit: 32)
            let titleText = translated(item, sourceKey: "title", hebrewKey: "title_he", limit: titleLimit)
            guard !id.isEmpty, !titleText.source.isEmpty else {
                continue
            }
            let topicText = translated(item, sourceKey: "topic", hebrewKey: "topic_he", limit: 60)
            let rawSteps = item["steps"] as? [Any] ?? []
            let hebrewSteps = item["steps_he"] as? [Any] ?? []
            let sourceStepPairs = rawSteps.enumerated().compactMap { index, value -> (Int, String)? in
                let text = clean(value, limit: originalLimit)
                return text.isEmpty ? nil : (index, text)
            }
            let sourceSteps = sourceStepPairs.map { $0.1 }
            let steps = sourceStepPairs.map { index, source in
                let hebrew = index < hebrewSteps.count ? cleanHebrew(hebrewSteps[index], limit: stepLimit) : ""
                return hebrew.isEmpty ? clean(source, limit: stepLimit) : hebrew
            }
            let at = min(max(0, intValue(item["at"]) ?? 0), steps.count)
            // A card with more than `maxSteps` steps shows the window that ends at the current step, so the lock
            // screen never shows every step done while work goes on (the bridge's content_state, same rule).
            let window = stepWindow(count: steps.count, at: at)
            var percent = intValue(item["percent"]).map { min(max(0, $0), 100) }
            if percent == nil, steps.count > maxSteps {
                // done / window would overstate the share; the true one, rounded like the bridge (half to even).
                percent = Int((Double(at) * 100.0 / Double(steps.count)).rounded(.toNearestOrEven))
            }
            progress.append(HarnessgramCockpitSnapshot.Progress(
                id: id,
                title: titleText.display,
                topic: topicText.display,
                steps: Array(steps[window]),
                done: at - window.lowerBound,
                percent: percent,
                topicURL: clean(item["topic_url"], limit: 200),
                finished: (item["finished"] as? Bool) ?? false,
                roomChannelId: HarnessgramCockpitLinks.channelId(fromTopicURL: clean(item["topic_url"], limit: 200)),
                updated: timeValue(item["updated"]),
                stale: item["stale"] as? Bool,
                originalTitle: titleText.source,
                originalTopic: topicText.source,
                originalSteps: Array(sourceSteps[window])
            ))
        }
        // Stable order: unfinished cards first, the most recently updated of them first; otherwise, and
        // for cards without an update time, as the Cockpit lists them.
        let ordered = progress.enumerated().sorted { lhs, rhs in
            if lhs.element.finished != rhs.element.finished {
                return !lhs.element.finished
            }
            if !lhs.element.finished, lhs.element.updated != rhs.element.updated {
                return (lhs.element.updated ?? -Double.infinity) > (rhs.element.updated ?? -Double.infinity)
            }
            return lhs.offset < rhs.offset
        }.map { $0.element }

        var radio: HarnessgramCockpitSnapshot.Radio?
        if let radioPlayer, let item = (try? JSONSerialization.jsonObject(with: radioPlayer)) as? [String: Any], item["ok"] as? Bool == true {
            let enabled = (item["enabled"] as? Bool) ?? false
            radio = HarnessgramCockpitSnapshot.Radio(enabled: enabled, on: enabled && ((item["on"] as? Bool) ?? false))
        }

        // The device snapshot and the authenticated panel expose the same summary under different keys.
        let today = root["today"]
        let todayValue = today is NSNull ? root["ownerToday"] : today ?? root["ownerToday"]
        return HarnessgramCockpitSnapshot(
            updatedAt: now,
            waitingCount: decisions.count,
            decisions: Array(decisions.prefix(HarnessgramCockpitSnapshot.maxDecisions)),
            runningAgents: agents.count,
            agents: Array(agents.prefix(HarnessgramCockpitSnapshot.maxAgents)),
            radio: radio,
            progress: ordered,
            botId: HarnessgramCockpitParser.botId(root["bot_id"]),
            pending: pendingCount(root["pending"]),
            appSwitches: HarnessgramCockpitSnapshot.AppSwitches.parse(root["appSwitches"] ?? root["app_switches"]),
            today: parseToday(todayValue, bridgeOrigin: bridgeOrigin)
        )
    }

    private static func parseToday(_ value: Any?, bridgeOrigin: URL?) -> HarnessgramCockpitSnapshot.Today {
        guard let item = value as? [String: Any] else {
            return .empty
        }
        var waiting: [HarnessgramCockpitSnapshot.Today.Waiting] = []
        for case let row as [String: Any] in (item["waiting"] as? [Any] ?? []) {
            let title = cleanHebrew(row["title"], limit: 60)
            guard !title.isEmpty, let age = todayCount(row["age_minutes"]),
                  let rawURL = row["url"] as? String, let url = HarnessgramCockpitLinks.todayURL(rawURL, bridgeOrigin: bridgeOrigin) else {
                continue
            }
            waiting.append(.init(title: title, ageMinutes: age, url: url))
            if waiting.count == HarnessgramCockpitSnapshot.Today.maxWaiting {
                break
            }
        }
        return .init(doneToday: todayCount(item["done_today"]) ?? 0, totalToday: todayCount(item["total_today"]) ?? 0, waiting: waiting)
    }

    private static func todayCount(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let count = Int(number.stringValue) else {
            return nil
        }
        return max(0, count)
    }

    /// Every open decision the panel lists, in its order and without the widget cap (the app's waiting list needs them
    /// all; the widget snapshot keeps `maxDecisions`). Same rules as the snapshot: stale ones and ones without a valid
    /// id or title are dropped.
    public static func openDecisions(state: Data) throws -> [HarnessgramCockpitSnapshot.Decision] {
        guard let root = (try? JSONSerialization.jsonObject(with: state)) as? [String: Any] else {
            throw ParseError.notJSON
        }
        guard root["ok"] as? Bool == true else {
            throw ParseError.notOK
        }
        return parseDecisions(root, now: Date())
    }

    static let optionLimit = 8

    /// `keepOld`: also a decision the panel marks only "old" (age alone). The bridge still takes an answer to it; only
    /// "ended" and "replaced" refuse one. The widgets leave old ones out, the native Cockpit lists them under "old".
    static func parseDecisions(_ root: [String: Any], now: Date, keepOld: Bool = false) -> [HarnessgramCockpitSnapshot.Decision] {
        // The panel's own clock ("now") with each decision's "age" gives when it was asked, the same instant on
        // every refresh; without "now" the device's clock stands in.
        let reference = timeValue(root["now"]) ?? now.timeIntervalSince1970
        var decisions: [HarnessgramCockpitSnapshot.Decision] = []
        for case let item as [String: Any] in (root["decisions"] as? [Any] ?? []) {
            guard let id = item["id"] as? String, HarnessgramCockpitLinks.isDecisionId(id) else {
                continue
            }
            // A decision the panel marks stale (its session ended or the question was asked again) no
            // longer waits on the owner and is never answerable.
            if let stale = item["stale"] as? String, !stale.isEmpty, !(keepOld && stale == "old") {
                continue
            }
            let titleText = translated(item, sourceKey: "title", hebrewKey: "title_he", limit: titleLimit)
            guard !titleText.source.isEmpty else {
                continue
            }
            let topicText = translated(item, sourceKey: "topic", hebrewKey: "topic_he", limit: 60)
            let detailText = translated(item, sourceKey: "detail", hebrewKey: "detail_he", limit: 1_500, multiline: true)
            let yesText = translated(item, sourceKey: "yes", hebrewKey: "yes_he", limit: 24)
            let noText = translated(item, sourceKey: "no", hebrewKey: "no_he", limit: 24)
            let url = clean(item["url"], limit: 200)
            // Optional fields the bridge will fill later (plan step 0): a missing or malformed value reads as nil.
            let kind = clean(item["kind"], limit: 24)
            let rawOptions = Array((item["options"] as? [Any] ?? []).prefix(optionLimit))
            let hebrewOptions = item["options_he"] as? [Any] ?? []
            let sourceOptionPairs = rawOptions.enumerated().compactMap { index, value -> (Int, String)? in
                let text = clean(value, limit: originalLimit)
                return text.isEmpty ? nil : (index, text)
            }
            let sourceOptions = sourceOptionPairs.map { $0.1 }
            let options = sourceOptionPairs.map { index, source in
                let hebrew = index < hebrewOptions.count ? cleanHebrew(hebrewOptions[index], limit: 60) : ""
                return hebrew.isEmpty ? clean(source, limit: 60) : hebrew
            }
            decisions.append(HarnessgramCockpitSnapshot.Decision(
                id: id,
                title: titleText.display,
                topic: topicText.display,
                yesLabel: yesText.display.isEmpty ? HarnessgramWidgetStrings.approve : yesText.display,
                noLabel: noText.display.isEmpty ? HarnessgramWidgetStrings.decline : noText.display,
                topicURL: url,
                sensitive: (item["sensitive"] as? Bool) ?? true,
                roomChannelId: HarnessgramCockpitLinks.channelId(fromTopicURL: url),
                kind: kind.isEmpty ? nil : kind,
                options: options.isEmpty ? nil : Array(options),
                detail: detailText.display.isEmpty ? nil : detailText.display,
                originalTitle: titleText.source,
                originalTopic: topicText.source,
                originalDetail: detailText.source,
                originalYesLabel: yesText.source.isEmpty ? nil : yesText.source,
                originalNoLabel: noText.source.isEmpty ? nil : noText.source,
                originalOptions: sourceOptions.isEmpty ? nil : sourceOptions,
                askedAt: ageValue(item["age"]).map { Date(timeIntervalSince1970: reference - Double($0)) }
            ))
        }
        return decisions
    }

    /// The bridge bot's user id from the panel ("bot_id"): a positive integer (JSON number, or a string of digits).
    static func botId(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber, !CFNumberIsFloatType(number as CFNumber), number.int64Value > 0 {
            return number.int64Value
        }
        if let text = value as? String, !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let id = Int64(text), id > 0 {
            return id
        }
        return nil
    }

    /// Whether the display differs from the bounded source fallback, rather than merely being shortened.
    public static func hasTranslation(_ display: String?, original: String?, limit: Int) -> Bool {
        guard let display, let original, !original.isEmpty else {
            return false
        }
        return display != clean(original, limit: limit)
    }

    /// Controls and bidi overrides are removed. Hebrew fields retain paragraph breaks and balanced FSI/PDI
    /// isolates, including after truncation; other fields retain their single-line sanitization.
    static func clean(_ value: Any?, limit: Int, preservingHebrewFormatting: Bool = false) -> String {
        guard let text = value as? String else {
            return ""
        }
        let banned: Set<UInt32> = [0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F]
        var scalars = String.UnicodeScalarView()
        let input = preservingHebrewFormatting ? text.replacingOccurrences(of: "\r\n", with: "\n") : text
        for scalar in input.unicodeScalars {
            if preservingHebrewFormatting && (scalar.value == 0x2068 || scalar.value == 0x2069) {
                scalars.append(scalar)
            } else if preservingHebrewFormatting && CharacterSet.newlines.contains(scalar) {
                scalars.append("\n")
            } else if banned.contains(scalar.value) {
                continue
            } else if scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .lineSeparator || scalar.properties.generalCategory == .paragraphSeparator {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
        }
        let collapsed: String
        if preservingHebrewFormatting {
            collapsed = balancedIsolates(String(scalars))
                .components(separatedBy: "\n")
                .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
                .joined(separator: "\n")
                .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            collapsed = String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        if collapsed.count <= limit {
            return collapsed
        }
        let truncated = String(collapsed.prefix(max(0, limit - 1))) + "…"
        return preservingHebrewFormatting ? balancedIsolates(truncated) : truncated
    }

    private static func balancedIsolates(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var openings: [Int] = []
        var unmatched: Set<Int> = []
        for (index, scalar) in scalars.enumerated() {
            if scalar.value == 0x2068 {
                openings.append(index)
            } else if scalar.value == 0x2069 && openings.popLast() == nil {
                unmatched.insert(index)
            }
        }
        unmatched.formUnion(openings)
        return String(String.UnicodeScalarView(scalars.enumerated().compactMap { index, scalar in
            return unmatched.contains(index) ? nil : scalar
        }))
    }

    /// Seconds since 1970 (the bridge sends a float): a finite, positive number; a bool, text or anything else is nil.
    static func timeValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            guard double.isFinite, double > 0 else {
                return nil
            }
            return double
        }
        return nil
    }

    /// A decision's age in whole seconds: a non-negative integer number under a year; text ("2m"), a bool, a
    /// fraction or anything else is nil (no age is shown rather than a guessed one).
    static func ageValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let seconds = Int(exactly: number.doubleValue), seconds >= 0, seconds < 366 * 24 * 3600 else {
            return nil
        }
        return seconds
    }

    /// An optional count, never a bool, fractional number, negative number or overflowing integer.
    static func pendingCount(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let count = Int(exactly: number.doubleValue), count >= 0 else {
            return nil
        }
        return count
    }

    static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let double = number.doubleValue
            guard double.isFinite, abs(double) < 1_000_000 else {
                return nil
            }
            return Int(double)
        }
        return nil
    }
}
