import XCTest
import HarnessgramCockpitKit
import HarnessgramHouseCore
import HarnessgramSettings

private final class MemoryKnockStorage: HouseKnockStorage {
    var record: HouseKnockRecord?

    func load() -> HouseKnockRecord? {
        return self.record
    }

    func save(_ record: HouseKnockRecord) {
        self.record = record
    }
}

final class HouseKnockLogicTests: XCTestCase {
    private func decision(_ id: String, sensitive: Bool = false, kind: String? = nil, options: [String]? = nil, yes: String = "כן", no: String = "לא") -> HarnessgramCockpitSnapshot.Decision {
        return HarnessgramCockpitSnapshot.Decision(id: id, title: "למזג?", topic: "פרויקט לדוגמה", yesLabel: yes, noLabel: no, topicURL: "https://t.me/c/900000002/9", sensitive: sensitive, roomChannelId: 900000002, kind: kind, options: options)
    }

    private func credential(authDate: Date) -> HarnessgramCockpitCredential {
        return HarnessgramCockpitCredential(initData: "x", origin: "https://mac.private.example.test:10000", authDate: authDate, configuration: HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"]))
    }

    // MARK: interception rule

    func testOnlyTheBridgeInItsOwnAgentChatsAsksAQuestionKnocks() {
        let good = HouseKnockRule.MessageFacts(authorIsPinnedBridgeBot: true, isForward: false, isViaBot: false, isInAgentChat: true, asksQuestion: true)
        XCTAssertTrue(HouseKnockRule.mayKnock(good))

        var other = good
        other.authorIsPinnedBridgeBot = false
        XCTAssertFalse(HouseKnockRule.mayKnock(other), "another bot, or a person, never knocks")

        var forward = good
        forward.isForward = true
        XCTAssertFalse(HouseKnockRule.mayKnock(forward), "a forward never knocks")

        var via = good
        via.isViaBot = true
        XCTAssertFalse(HouseKnockRule.mayKnock(via), "a message sent through another bot never knocks")

        var elsewhere = good
        elsewhere.isInAgentChat = false
        XCTAssertFalse(HouseKnockRule.mayKnock(elsewhere), "outside the agent chats the banner stays")

        var plain = good
        plain.asksQuestion = false
        XCTAssertFalse(HouseKnockRule.mayKnock(plain), "a plain bridge message keeps Telegram's banner")
    }

    // MARK: ledger

    func testASecondPokeDoesNotKnockForTheSameDecision() {
        let ledger = HouseKnockLedger(storage: MemoryKnockStorage())
        // First use: baseline with a single open decision, which is the new one.
        XCTAssertEqual(ledger.newDecisions(open: [decision("a")]).map(\.id), ["a"])
        ledger.markKnocked("a")
        XCTAssertEqual(ledger.newDecisions(open: [decision("a")]).map(\.id), [])
        XCTAssertEqual(ledger.newDecisions(open: [decision("b"), decision("a")]).map(\.id), ["b"])
    }

    func testTheKnockedSetSurvivesARelaunch() {
        let storage = MemoryKnockStorage()
        let first = HouseKnockLedger(storage: storage)
        _ = first.newDecisions(open: [decision("a")])
        first.markKnocked("a")
        // A new ledger over the same storage is the app after a relaunch.
        let second = HouseKnockLedger(storage: storage)
        XCTAssertTrue(second.hasKnocked("a"))
        XCTAssertEqual(second.newDecisions(open: [decision("a")]).map(\.id), [])
    }

    func testFirstUseKnocksOnlyTheNewestAndRecordsTheRestSilently() {
        let storage = MemoryKnockStorage()
        let ledger = HouseKnockLedger(storage: storage)
        let open = [decision("c"), decision("b"), decision("a")]
        XCTAssertEqual(ledger.newDecisions(open: open).map(\.id), ["c"])
        XCTAssertTrue(ledger.hasKnocked("b"))
        XCTAssertTrue(ledger.hasKnocked("a"))
        XCTAssertFalse(ledger.hasKnocked("c"), "the one that knocks is recorded when its sheet appears")
        // A later decision knocks normally.
        XCTAssertEqual(ledger.newDecisions(open: [decision("d")] + open).map(\.id), ["d", "c"])
    }

    func testLaterIsTheSameAsKnockedAndTheDecisionStaysOpen() {
        let ledger = HouseKnockLedger(storage: MemoryKnockStorage())
        _ = ledger.newDecisions(open: [])
        ledger.markKnocked("a")
        // "Later" marks it knocked: it does not knock again, and nothing here removes it from the open list.
        let open = [decision("a")]
        XCTAssertEqual(ledger.newDecisions(open: open), [])
        XCTAssertEqual(open.count, 1)
    }

    func testOldEntriesAreForgottenAndTheSetIsCapped() {
        var clock = Date(timeIntervalSince1970: 1_763_200_000)
        let ledger = HouseKnockLedger(storage: MemoryKnockStorage(), now: { clock })
        _ = ledger.newDecisions(open: [])
        ledger.markKnocked("old")
        clock = clock.addingTimeInterval(HouseKnockLedger.memory + 60)
        ledger.markKnocked("fresh")
        XCTAssertFalse(ledger.hasKnocked("old"))
        XCTAssertTrue(ledger.hasKnocked("fresh"))

        for index in 0 ..< (HouseKnockLedger.maxEntries + 20) {
            clock = clock.addingTimeInterval(1)
            ledger.markKnocked(String(format: "%016x", index))
        }
        XCTAssertTrue(ledger.hasKnocked(String(format: "%016x", HouseKnockLedger.maxEntries + 19)))
        XCTAssertFalse(ledger.hasKnocked(String(format: "%016x", 0)))
    }

    func testUserDefaultsStorageKeepsOneRecordPerAccount() {
        let suite = "HouseKnockLogicTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let one = HouseKnockUserDefaultsStorage(accountId: 1, defaults: defaults)
        let two = HouseKnockUserDefaultsStorage(accountId: 2, defaults: defaults)
        one.save(HouseKnockRecord(initialized: true, knocked: ["a": Date(timeIntervalSince1970: 1_763_200_000)]))
        XCTAssertEqual(one.load()?.knocked.keys.sorted(), ["a"])
        XCTAssertNil(two.load())
    }

    // MARK: queue

    func testAPokeShowsAtMostThreeSheets() {
        let new = (1 ... 5).map { decision("d\($0)") }
        let batch = HouseKnockQueue.batch(from: new)
        XCTAssertEqual(batch.show.map(\.id), ["d1", "d2", "d3"])
        XCTAssertEqual(batch.skipped.map(\.id), ["d4", "d5"])
        XCTAssertEqual(HouseKnockQueue.batch(from: []).show, [])
    }

    // MARK: row plan (Face ID stays with the sensitive ones)

    func testASensitiveDecisionIsNeverAnsweredInPlace() {
        let now = Date(timeIntervalSince1970: 1_763_200_000)
        let fresh = credential(authDate: now.addingTimeInterval(-10))
        let plan = HouseWaitingRowPlan.make(decision: decision("a", sensitive: true), credential: fresh, now: now)
        XCTAssertEqual(plan.style, .approveWithFaceID)
    }

    func testAPlainDecisionIsAnsweredInPlaceOnlyWithAFreshLogin() {
        let now = Date(timeIntervalSince1970: 1_763_200_000)
        let fresh = credential(authDate: now.addingTimeInterval(-10))
        let stale = credential(authDate: now.addingTimeInterval(-HarnessgramCockpitCredential.answerWindow - 5))
        XCTAssertEqual(HouseWaitingRowPlan.make(decision: decision("a"), credential: fresh, now: now).style, .answerInPlace)
        XCTAssertEqual(HouseWaitingRowPlan.make(decision: decision("a"), credential: stale, now: now).style, .answerViaApp)
        XCTAssertEqual(HouseWaitingRowPlan.make(decision: decision("a"), credential: nil, now: now).style, .answerViaApp)
    }

    func testAChoiceQuestionOpensTheRoomAndNeverGuessesAnAnswer() {
        let now = Date(timeIntervalSince1970: 1_763_200_000)
        let fresh = credential(authDate: now)
        let choice = decision("a", kind: "choice", options: ["א", "ב", "ג"])
        XCTAssertEqual(HouseWaitingRowPlan.make(decision: choice, credential: fresh, now: now).style, .chooseInRoom)
        // A "choice" without usable options is a yes/no question, as in the waiting item.
        let broken = decision("b", kind: "choice", options: ["א"])
        XCTAssertEqual(HouseWaitingRowPlan.make(decision: broken, credential: fresh, now: now).style, .answerInPlace)
    }

    func testTheRowKeepsTheBridgesAnswerLabels() {
        let now = Date(timeIntervalSince1970: 1_763_200_000)
        let plan = HouseWaitingRowPlan.make(decision: decision("a", yes: "לשלוח", no: "לראות קודם"), credential: nil, now: now)
        XCTAssertEqual(plan.yesLabel, "לשלוח")
        XCTAssertEqual(plan.noLabel, "לראות קודם")
        let empty = HouseWaitingRowPlan.make(decision: decision("a", yes: "", no: ""), credential: nil, now: now)
        XCTAssertEqual(empty.yesLabel, "כן")
        XCTAssertEqual(empty.noLabel, "לא")
    }

    // MARK: Hebrew counts

    func testHebrewCounts() {
        XCTAssertEqual(HouseKnockText.thingsCount(1), "דבר אחד")
        XCTAssertEqual(HouseKnockText.thingsCount(2), "שני דברים")
        XCTAssertEqual(HouseKnockText.thingsCount(3), "3 דברים")
        XCTAssertNil(HouseKnockText.moreWaiting(0))
        XCTAssertEqual(HouseKnockText.moreWaiting(1), "עוד אחד מחכה לך")
        XCTAssertEqual(HouseKnockText.moreWaiting(4), "עוד 4 מחכים לך")
    }

    func testRoomNameAndDetailFromTheTopicLine() {
        XCTAssertEqual(HouseKnockText.roomName(fromTopic: "פרויקט לדוגמה: מסך כניסה"), "פרויקט לדוגמה")
        XCTAssertEqual(HouseKnockText.topicDetail(fromTopic: "פרויקט לדוגמה: מסך כניסה"), "מסך כניסה")
        XCTAssertEqual(HouseKnockText.roomName(fromTopic: "תדריך בוקר"), "תדריך בוקר")
        XCTAssertNil(HouseKnockText.topicDetail(fromTopic: "תדריך בוקר"))
        XCTAssertEqual(HouseKnockText.roomName(fromTopic: ""), "חדר")
        XCTAssertEqual(HouseKnockText.roomName(fromTopic: " : x"), "חדר")
    }

    func testTheQuestionOfAPlainMessageIsItsFirstLineAndIsCut() {
        XCTAssertEqual(HouseKnockText.questionLine(fromMessageText: "\n  למזג?  \nעוד שורה"), "למזג?")
        XCTAssertNil(HouseKnockText.questionLine(fromMessageText: "  \n "))
        let long = String(repeating: "מילה ", count: 60)
        let cut = HouseKnockText.questionLine(fromMessageText: long, limit: 40)!
        XCTAssertLessThanOrEqual(cut.count, 41)
        XCTAssertTrue(cut.hasSuffix("\u{2026}"))
    }
}
