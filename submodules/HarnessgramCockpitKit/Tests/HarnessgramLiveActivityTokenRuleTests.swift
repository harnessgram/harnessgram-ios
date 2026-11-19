import XCTest
@testable import HarnessgramCockpitKit

/// The owner's phone never sent a Live Activity push token: activities without one are requested again once, and the
/// app tells the bridge why a token is missing with an allow-listed code only.
final class HarnessgramLiveActivityTokenRuleTests: XCTestCase {
    typealias Rule = HarnessgramLiveActivityTokenRule
    let start = Date(timeIntervalSince1970: 1_000_000)

    func testActivityWithoutTokenIsReplacedOnceAfterTheGrace() {
        let late = start.addingTimeInterval(Rule.grace)
        XCTAssertFalse(Rule.shouldReplace(cardId: "c1", hasToken: false, firstSeen: start, now: start.addingTimeInterval(Rule.grace - 1), retried: []))
        XCTAssertTrue(Rule.shouldReplace(cardId: "c1", hasToken: false, firstSeen: start, now: late, retried: []))
        XCTAssertFalse(Rule.shouldReplace(cardId: "c1", hasToken: true, firstSeen: start, now: late, retried: []))
        XCTAssertFalse(Rule.shouldReplace(cardId: "c1", hasToken: false, firstSeen: nil, now: late, retried: []))
        // Never twice for one card (no loop), and never the app-local overflow summary.
        XCTAssertFalse(Rule.shouldReplace(cardId: "c1", hasToken: false, firstSeen: start, now: late, retried: ["c1"]))
        XCTAssertFalse(Rule.shouldReplace(cardId: HarnessgramTaskActivityPlan.summaryCardId, hasToken: false, firstSeen: start, now: late, retried: []))
    }

    func testMissingTokenIsReportedOnlyAfterTheRetryAndOnce() {
        let late = start.addingTimeInterval(Rule.grace + 5)
        XCTAssertFalse(Rule.shouldReportMissing(cardId: "c1", hasToken: false, firstSeen: start, now: late, retried: [], reported: []))
        XCTAssertTrue(Rule.shouldReportMissing(cardId: "c1", hasToken: false, firstSeen: start, now: late, retried: ["c1"], reported: []))
        XCTAssertFalse(Rule.shouldReportMissing(cardId: "c1", hasToken: false, firstSeen: start, now: late, retried: ["c1"], reported: ["c1"]))
        XCTAssertFalse(Rule.shouldReportMissing(cardId: "c1", hasToken: true, firstSeen: start, now: late, retried: ["c1"], reported: []))
        XCTAssertFalse(Rule.shouldReportMissing(cardId: "c1", hasToken: false, firstSeen: start, now: start, retried: ["c1"], reported: []))
        XCTAssertFalse(Rule.shouldReportMissing(cardId: HarnessgramTaskActivityPlan.summaryCardId, hasToken: false, firstSeen: start, now: late, retried: [HarnessgramTaskActivityPlan.summaryCardId], reported: []))
    }

    func testRetriedListIsDedupedAndCapped() {
        var list: [String] = []
        for index in 0 ..< (Rule.maxRetried + 10) {
            list = Rule.remember("card-\(index)", in: list)
        }
        list = Rule.remember("card-\(Rule.maxRetried + 9)", in: list)
        XCTAssertEqual(list.count, Rule.maxRetried)
        XCTAssertEqual(list.last, "card-\(Rule.maxRetried + 9)")
        XCTAssertEqual(list.first, "card-10")
        XCTAssertEqual(Set(list).count, list.count)
    }

    func testRequestFailureCodesAlwaysPassTheBridgeAllowList() {
        XCTAssertEqual(Rule.requestFailed(caseName: "visibility", domain: "com.apple.ActivityKit.ActivityAuthorizationError", code: 3), "request-failed:visibility.3")
        XCTAssertEqual(Rule.requestFailed(caseName: nil, domain: "NSCocoaErrorDomain", code: -4), "request-failed:NSCocoaErrorDomain.-4")
        let long = Rule.requestFailed(caseName: nil, domain: String(repeating: "a", count: 200) + " /\u{05D0}", code: 42)
        XCTAssertTrue(long.hasSuffix(".42"))
        XCTAssertEqual(Rule.requestFailed(caseName: "\u{05D0} /", domain: "", code: 0).isEmpty, false)
        for code in [long, Rule.requestFailed(caseName: "Activity Authorization Error (rawValue: 1)", domain: "x", code: 1), Rule.requestFailed(caseName: "\u{05D0}", domain: "", code: 0), Rule.noTokenAfterGrace, "request-failed"] {
            XCTAssertTrue(Rule.isProblemCode(code), code)
        }
        // "push-disabled" is never sent by the app (no such per-activity signal exists).
        for code in ["", "free text", "request-failed:", "request-failed:a b", "request-failed:" + String(repeating: "x", count: 65), "no-token", "push-disabled"] {
            XCTAssertFalse(Rule.isProblemCode(code), code)
        }
    }

    func testProblemBodyMatchesTheBridgeContract() throws {
        let body = try XCTUnwrap(HarnessgramCockpitClient.liveActivityProblemBody(cardId: "card-1", problem: "request-failed:visibility.3"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["card_id": "card-1", "problem": "request-failed:visibility.3"])
        XCTAssertNil(HarnessgramCockpitClient.liveActivityProblemBody(cardId: "card-1", problem: "free text"))
        XCTAssertNil(HarnessgramCockpitClient.liveActivityProblemBody(cardId: "bad id/../x", problem: Rule.noTokenAfterGrace))
    }

    /// Review of dca68b29: the new activity is requested before the old one ends, and the card counts as retried
    /// only when that worked; a visibility refusal leaves everything as it was.
    func testReplacementRequestsTheNewActivityFirstAndEndsTheOldOnlyAfterSuccess() throws {
        let success = Rule.replaceSteps(requestSucceeded: true)
        XCTAssertEqual(success.first, .requestWithToken)
        let request = try XCTUnwrap(success.firstIndex(of: .requestWithToken))
        let end = try XCTUnwrap(success.firstIndex(of: .endOld))
        XCTAssertLessThan(request, end)
        XCTAssertTrue(success.contains(.rememberRetried))
        XCTAssertFalse(success.contains(.reportProblem))
        XCTAssertEqual(Rule.replaceSteps(requestSucceeded: false, refusedForVisibility: true), [.requestWithToken])
        let failed = Rule.replaceSteps(requestSucceeded: false, refusedForVisibility: false)
        XCTAssertFalse(failed.contains(.endOld))
        XCTAssertEqual(failed, [.requestWithToken, .rememberRetried, .reportProblem])
    }

    /// Review of dca68b29: the summary card is never replaced, an activity whose token arrived is only updated, and
    /// nothing is requested or replaced while the app is not in the foreground.
    func testTheUpdateLoopSkipsTheSummaryAndWaitsForTheForeground() {
        let summary = HarnessgramTaskActivityPlan.summaryCardId
        XCTAssertEqual(Rule.loopAction(cardId: summary, live: true, liveHasToken: false, markedForReplace: true, appActive: true), .update)
        XCTAssertEqual(Rule.loopAction(cardId: summary, live: false, liveHasToken: false, markedForReplace: false, appActive: true), .request)
        XCTAssertEqual(Rule.loopAction(cardId: "c1", live: true, liveHasToken: false, markedForReplace: true, appActive: true), .replace)
        XCTAssertEqual(Rule.loopAction(cardId: "c1", live: true, liveHasToken: true, markedForReplace: true, appActive: true), .update)
        XCTAssertEqual(Rule.loopAction(cardId: "c1", live: true, liveHasToken: false, markedForReplace: true, appActive: false), .update)
        XCTAssertEqual(Rule.loopAction(cardId: "c1", live: true, liveHasToken: false, markedForReplace: false, appActive: true), .update)
        XCTAssertEqual(Rule.loopAction(cardId: "c1", live: false, liveHasToken: false, markedForReplace: true, appActive: true), .request)
        XCTAssertEqual(Rule.loopAction(cardId: "c1", live: false, liveHasToken: false, markedForReplace: false, appActive: false), .wait)
    }

    /// Review of dca68b29: a problem never overwrites a token or an end waiting for the same card.
    func testAProblemNeverReplacesAWaitingTokenOrEnd() {
        XCTAssertTrue(Rule.queuesProblem(over: nil))
        XCTAssertTrue(Rule.queuesProblem(over: .problem))
        XCTAssertFalse(Rule.queuesProblem(over: .token))
        XCTAssertFalse(Rule.queuesProblem(over: .ended))
    }

    /// Build 31 diagnosis: a card past the grace without a token reports the APNs registration state, in a shape the
    /// bridge's allow-list (src/ctb/panel.py LA_PROBLEM) accepts.
    func testTheApnsStateMapsToAnAllowListedProblemCode() {
        XCTAssertEqual(Rule.apnsProblem(state: .registered, unregisterCalls: 0), "request-failed:apns-registered.unreg0")
        XCTAssertEqual(Rule.apnsProblem(state: .unknown, unregisterCalls: 2), "request-failed:apns-unknown.unreg2")
        XCTAssertEqual(Rule.apnsProblem(state: .failed(code: 3000), unregisterCalls: 0), "request-failed:apns-fail.3000.unreg0")
        XCTAssertEqual(Rule.apnsProblem(state: .failed(code: -1), unregisterCalls: 1), "request-failed:apns-fail.-1.unreg1")
        XCTAssertEqual(Rule.apnsProblem(state: .invalidatedByServer, unregisterCalls: 0), "request-failed:apns-invalidated.unreg0")
        for state: Rule.ApnsState in [.unknown, .registered, .failed(code: Int.min), .failed(code: Int.max), .invalidatedByServer] {
            let code = Rule.apnsProblem(state: state, unregisterCalls: Int.max)
            XCTAssertTrue(Rule.isProblemCode(code), code)
            XCTAssertNotNil(HarnessgramCockpitClient.liveActivityProblemBody(cardId: "card-1", problem: code), code)
        }
    }

    /// Live Activity tokens up to 256 bytes reach the bridge (they were dropped above 128).
    func testTokensUpTo256BytesAreSent() throws {
        for count in [32, 100, 128, 129, 256] {
            let body = try XCTUnwrap(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "card-1", token: Data(repeating: 0xab, count: count), sandbox: false), "\(count)")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json["token"]?.count, count * 2)
        }
        XCTAssertNil(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "card-1", token: Data(repeating: 0xab, count: 257), sandbox: false))
        XCTAssertNil(HarnessgramCockpitClient.liveActivityTokenBody(cardId: "card-1", token: Data(), sandbox: false))
    }
}
