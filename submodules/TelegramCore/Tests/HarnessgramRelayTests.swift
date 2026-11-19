import XCTest
import HarnessgramSettings
@testable import TelegramCore

/// The home relay: Telegram goes through it while it answers, directly when it does not, and calls never use it.
final class HarnessgramRelayTests: XCTestCase {
    private let relay = ProxyServerSettings(host: "relay.example.test", port: 1080, connection: .socks5(username: nil, password: nil))
    private let other = ProxyServerSettings(host: "proxy.example.net", port: 443, connection: .socks5(username: nil, password: nil))

    func testRelayUsesConfiguredSocks5WithoutCredentials() throws {
        let configured = try XCTUnwrap(HarnessgramRelay.server(configuration: HarnessgramLocalConfig(relayHost: "relay.example.test", relayPort: 1081)))
        XCTAssertEqual(configured.host, "relay.example.test")
        XCTAssertEqual(configured.port, 1081)
        XCTAssertEqual(configured.connection, .socks5(username: nil, password: nil))
        XCTAssertNil(HarnessgramRelay.server(configuration: HarnessgramLocalConfig(relayHost: "relay.example.test", relayPort: 0)))
    }

    func testMissingRelayConfigurationDoesNotInstallOrProbeAnEndpoint() {
        XCTAssertNil(HarnessgramHomeRelay.configuredHost(HarnessgramLocalConfig()))
        let settings = ProxySettings(enabled: true, servers: [self.other], activeServer: self.other, useForCalls: true)
        XCTAssertEqual(HarnessgramRelay.apply(settings, switchOn: true, useRelay: true, relay: nil, stale: nil), settings)
    }

    func testBuildWithoutRelaySettingsRemovesARememberedRelay() {
        let active = ProxySettings(enabled: true, servers: [self.relay, self.other], activeServer: self.relay, useForCalls: false)
        for switchOn in [true, false] {
            let result = HarnessgramRelay.apply(active, switchOn: switchOn, useRelay: false, relay: nil, stale: self.relay)
            XCTAssertFalse(result.enabled)
            XCTAssertNil(result.activeServer)
            XCTAssertEqual(result.servers, [self.other])
        }
        let otherActive = ProxySettings(enabled: true, servers: [self.relay, self.other], activeServer: self.other, useForCalls: true)
        let kept = HarnessgramRelay.apply(otherActive, switchOn: true, useRelay: false, relay: nil, stale: self.relay)
        XCTAssertTrue(kept.enabled)
        XCTAssertEqual(kept.activeServer, self.other)
        XCTAssertEqual(kept.servers, [self.other])
    }

    func testSwitchOnAddsTheRelayAndCallsNeverUseAProxy() {
        var settings = ProxySettings(enabled: false, servers: [self.other], activeServer: nil, useForCalls: true)
        settings = HarnessgramRelay.apply(settings, switchOn: true, useRelay: true, relay: self.relay)
        XCTAssertEqual(settings.servers, [self.relay, self.other])
        XCTAssertEqual(settings.effectiveActiveServer, self.relay)
        XCTAssertFalse(settings.useForCalls)
        // Applying again changes nothing (no duplicates).
        XCTAssertEqual(HarnessgramRelay.apply(settings, switchOn: true, useRelay: true, relay: self.relay), settings)
        for useRelay in [false, true] {
            for useForCalls in [false, true] {
                let result = HarnessgramRelay.apply(ProxySettings(enabled: true, servers: [], activeServer: self.relay, useForCalls: useForCalls), switchOn: true, useRelay: useRelay, relay: self.relay)
                XCTAssertFalse(result.useForCalls)
            }
        }
    }

    func testRelayDownMeansDirect() {
        let up = HarnessgramRelay.apply(.defaultSettings, switchOn: true, useRelay: true, relay: self.relay)
        let down = HarnessgramRelay.apply(up, switchOn: true, useRelay: false, relay: self.relay)
        XCTAssertNil(down.effectiveActiveServer)
        XCTAssertTrue(down.servers.contains(self.relay))
        // A proxy the owner chose himself is left alone while the relay is down.
        let own = ProxySettings(enabled: true, servers: [self.relay, self.other], activeServer: self.other, useForCalls: false)
        XCTAssertEqual(HarnessgramRelay.apply(own, switchOn: true, useRelay: false, relay: self.relay).effectiveActiveServer, self.other)
    }

    func testSwitchOffTurnsOnlyTheRelayOff() {
        let up = HarnessgramRelay.apply(.defaultSettings, switchOn: true, useRelay: true, relay: self.relay)
        XCTAssertNil(HarnessgramRelay.apply(up, switchOn: false, useRelay: true, relay: self.relay).effectiveActiveServer)
        let own = ProxySettings(enabled: true, servers: [self.other], activeServer: self.other, useForCalls: true)
        XCTAssertEqual(HarnessgramRelay.apply(own, switchOn: false, useRelay: true, relay: self.relay), own)
    }

    func testStartsDirectAndMovesToTheRelayWhenItAnswers() {
        var monitor = HarnessgramRelay.Monitor()
        XCTAssertEqual(monitor.mode, .direct)
        monitor.probe(reachable: false, at: 0.0)
        XCTAssertEqual(monitor.mode, .direct)
        monitor.probe(reachable: true, at: 1.0)
        XCTAssertEqual(monitor.mode, .relay)
    }

    func testTwoFailedProbesWithinFiveSecondsFallBackAndTheRelayComesBack() {
        var monitor = HarnessgramRelay.Monitor()
        monitor.probe(reachable: true, at: 0.0)
        monitor.probe(reachable: false, at: 10.0)
        XCTAssertEqual(monitor.mode, .relay, "one failure is not enough")
        monitor.probe(reachable: false, at: 20.0)
        XCTAssertEqual(monitor.mode, .relay, "failures far apart do not count together")
        monitor.probe(reachable: false, at: 22.5)
        XCTAssertEqual(monitor.mode, .direct)
        // The next regular probe that answers brings the relay back.
        monitor.probe(reachable: false, at: 82.5)
        XCTAssertEqual(monitor.mode, .direct)
        monitor.probe(reachable: true, at: 142.5)
        XCTAssertEqual(monitor.mode, .relay)
        // A success between failures resets the count.
        monitor.probe(reachable: false, at: 200.0)
        monitor.probe(reachable: true, at: 201.0)
        monitor.probe(reachable: false, at: 202.0)
        XCTAssertEqual(monitor.mode, .relay)
    }

    func testConnectingThroughTheRelayForTenSecondsFallsBackAndWaitsLongerEachTime() {
        var monitor = HarnessgramRelay.Monitor()
        monitor.probe(reachable: true, at: 0.0)
        monitor.connection(connectingThroughProxy: true, online: false, at: 1.0)
        monitor.check(at: 10.0)
        XCTAssertEqual(monitor.mode, .relay)
        monitor.check(at: 11.5)
        XCTAssertEqual(monitor.mode, .direct)
        // The relay still answers TCP, but it is not retried before its wait.
        monitor.probe(reachable: true, at: 30.0)
        XCTAssertEqual(monitor.mode, .direct)
        monitor.probe(reachable: true, at: 11.5 + HarnessgramRelay.Monitor.probeInterval)
        XCTAssertEqual(monitor.mode, .relay)
        monitor.connection(connectingThroughProxy: true, online: false, at: 100.0)
        monitor.check(at: 111.0)
        XCTAssertEqual(monitor.mode, .direct)
        XCTAssertEqual(monitor.retryAfter, 111.0 + 2.0 * HarnessgramRelay.Monitor.probeInterval)
    }

    func testConnectingDirectlyOrOnlineNeverFallsBack() {
        var monitor = HarnessgramRelay.Monitor()
        monitor.probe(reachable: true, at: 0.0)
        monitor.connection(connectingThroughProxy: true, online: false, at: 1.0)
        monitor.connection(connectingThroughProxy: false, online: true, at: 5.0)
        monitor.check(at: 60.0)
        XCTAssertEqual(monitor.mode, .relay)
        monitor.connection(connectingThroughProxy: false, online: false, at: 61.0)
        monitor.check(at: 120.0)
        XCTAssertEqual(monitor.mode, .relay)
    }

    func testTheSwitchIsOnByDefault() {
        let suite = "HarnessgramRelayTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(HarnessgramSettings(defaults: defaults).connectThroughHomeRelay)
    }

    func testHandEditsAreCorrectedToTheRelayState() {
        let down = HarnessgramRelay.apply(.defaultSettings, switchOn: true, useRelay: false, relay: self.relay)
        XCTAssertFalse(HarnessgramRelay.needsCorrection(down, switchOn: true, useRelay: false, relay: self.relay))
        // The relay switched on by hand while it is down.
        var manual = down
        manual.enabled = true
        manual.activeServer = self.relay
        XCTAssertTrue(HarnessgramRelay.needsCorrection(manual, switchOn: true, useRelay: false, relay: self.relay))
        XCTAssertNil(HarnessgramRelay.apply(manual, switchOn: true, useRelay: false, relay: self.relay).effectiveActiveServer)
        // Calls set to use the proxy while the relay is up.
        var calls = HarnessgramRelay.apply(.defaultSettings, switchOn: true, useRelay: true, relay: self.relay)
        calls.useForCalls = true
        XCTAssertTrue(HarnessgramRelay.needsCorrection(calls, switchOn: true, useRelay: true, relay: self.relay))
        XCTAssertFalse(HarnessgramRelay.apply(calls, switchOn: true, useRelay: true, relay: self.relay).useForCalls)
    }
}
