import XCTest
import HarnessgramSettings

final class HarnessgramSettingsTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "HarnessgramSettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testDefaultsAreInCode() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            XCTAssertTrue(settings.recordWithBuiltInMic)
            XCTAssertTrue(settings.autoDownloadInApprovedChats)
            XCTAssertTrue(settings.connectThroughHomeRelay)
            XCTAssertFalse(settings.justifiedText)
            XCTAssertEqual(settings.lineSpacing, .normal)
            XCTAssertEqual(HarnessgramSettings.LineSpacing.normal.factor, 0.12, accuracy: 0.0001)
            XCTAssertGreaterThan(HarnessgramSettings.LineSpacing.comfortable.factor, HarnessgramSettings.LineSpacing.normal.factor)
        }
    }

    func testValuesPersistAndCorruptValuesFallBackToDefaults() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            settings.justifiedText = true
            settings.lineSpacing = .comfortable
            settings.recordWithBuiltInMic = false
            let reloaded = HarnessgramSettings(defaults: defaults)
            XCTAssertTrue(reloaded.justifiedText)
            XCTAssertEqual(reloaded.lineSpacing, .comfortable)
            XCTAssertFalse(reloaded.recordWithBuiltInMic)
            defaults.set("loose", forKey: HarnessgramSettings.Key.lineSpacing.rawValue)
            defaults.set("yes", forKey: HarnessgramSettings.Key.justifiedText.rawValue)
            XCTAssertEqual(reloaded.lineSpacing, .normal)
            XCTAssertFalse(reloaded.justifiedText)
        }
    }

    /// Build 22: the Harnessgram theme is "none" (the owner's Telegram theme) until chosen; the default is never stored.
    func testTheThemeChoicePersists() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            XCTAssertEqual(settings.theme, .none)
            settings.theme = .cockpitNight
            XCTAssertEqual(HarnessgramSettings(defaults: defaults).theme, .cockpitNight)
            settings.theme = .none
            XCTAssertNil(defaults.object(forKey: HarnessgramSettings.Key.theme.rawValue))
            defaults.set("neon", forKey: HarnessgramSettings.Key.theme.rawValue)
            XCTAssertEqual(settings.theme, .none)
        }
    }

    /// The policy store keeps approvals under "Harnessgram." keys (and migrates every such key); the
    /// settings never write into that namespace.
    func testSettingsKeysStayOutOfThePolicyNamespace() {
        for key in HarnessgramSettings.Key.allCases {
            XCTAssertFalse(key.rawValue.hasPrefix("Harnessgram."), key.rawValue)
            XCTAssertTrue(key.rawValue.hasPrefix("HarnessgramSettings."), key.rawValue)
        }
    }

    func testReadingDefaultsAndClampedTextSize() {
        self.withDefaults { defaults in
            let settings = HarnessgramSettings(defaults: defaults)
            XCTAssertEqual(settings.messageFont, .system)
            XCTAssertEqual(settings.fontWeight, .regular)
            XCTAssertEqual(settings.textSizeSteps, 0)
            XCTAssertEqual(settings.bubbleWidth, .normal)
            XCTAssertEqual(settings.messageFontSize(base: 17.0), 17.0)
            settings.textSizeSteps = 9
            XCTAssertEqual(settings.textSizeSteps, 4)
            XCTAssertEqual(settings.messageFontSize(base: 17.0), 21.0)
            settings.textSizeSteps = -9
            XCTAssertEqual(settings.textSizeSteps, -2)
            defaults.set(40, forKey: HarnessgramSettings.Key.textSizeSteps.rawValue)
            XCTAssertEqual(settings.textSizeSteps, 4)
            settings.messageFont = .frankRuhlLibre
            settings.fontWeight = .semibold
            settings.bubbleWidth = .wide
            let reloaded = HarnessgramSettings(defaults: defaults)
            XCTAssertEqual(reloaded.messageFont, .frankRuhlLibre)
            XCTAssertEqual(reloaded.fontWeight, .semibold)
            XCTAssertEqual(reloaded.bubbleWidth, .wide)
            defaults.set("comic", forKey: HarnessgramSettings.Key.messageFont.rawValue)
            XCTAssertEqual(reloaded.messageFont, .system)
            XCTAssertEqual(HarnessgramSettings.FontWeight.allCases.map(\.value), [300.0, 400.0, 500.0, 600.0])
        }
    }

    func testListenLinkBecomesItsPlaylist() {
        let token = "AbCdEfGhIjKlMnOpQrStUvWxYz012345-_"
        XCTAssertEqual(HarnessgramRadioLink.streamURL(fromListenLink: "https://panel.example.net/listen/\(token)")?.absoluteString, "https://panel.example.net/listen/\(token)/live.m3u8")
        XCTAssertEqual(HarnessgramRadioLink.streamURL(fromListenLink: " https://panel.example.net/listen/\(token)/ ")?.absoluteString, "https://panel.example.net/listen/\(token)/live.m3u8")
        XCTAssertEqual(HarnessgramRadioLink.streamURL(fromListenLink: "https://panel.example.net/listen/\(token)/live.m3u8")?.absoluteString, "https://panel.example.net/listen/\(token)/live.m3u8")
        XCTAssertEqual(HarnessgramRadioLink.streamURL(fromListenLink: "https://panel.example.net:8443/base/listen/\(token)?x=1#y")?.absoluteString, "https://panel.example.net:8443/base/listen/\(token)/live.m3u8")
    }

    func testAnythingButAnHttpsListenLinkIsRefused() {
        let token = "AbCdEfGhIjKlMnOpQrStUvWxYz012345"
        for link in [nil, "", "http://panel.example.net/listen/\(token)", "ftp://panel.example.net/listen/\(token)", "https:///listen/\(token)", "https://user:pw@panel.example.net/listen/\(token)", "https://panel.example.net/radio/live.m3u8", "https://panel.example.net/listen/short", "https://panel.example.net/listen/\(token)/segment-1.ts", "https://panel.example.net/listen/\(token)/../api", "https://panel.example.net/listen/%2E%2E%2Fapi%2Fxxxxxxxxxx", "not a link"] as [String?] {
            XCTAssertNil(HarnessgramRadioLink.streamURL(fromListenLink: link), String(describing: link))
        }
    }

    func testRadioDeepLinkCarriesAValidListenLink() {
        let token = "AbCdEfGhIjKlMnOpQrStUvWxYz012345"
        let listen = "https://panel.example.net/listen/\(token)"
        let encoded = listen.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        XCTAssertEqual(HarnessgramRadioLink.listenLink(fromDeepLink: "harnessgram://radio?link=\(encoded)"), listen)
        XCTAssertEqual(HarnessgramRadioLink.listenLink(fromDeepLink: "harnessgram://radio?link=\(listen)"), listen, "unencoded")
        XCTAssertEqual(HarnessgramRadioLink.listenLink(fromDeepLink: "tg://harnessgram/radio?link=\(encoded)"), listen, "Telegram button form")
        XCTAssertEqual(HarnessgramRadioLink.listenLink(fromDeepLink: "HARNESSGRAM://Radio/?link=\(encoded)"), listen)
        XCTAssertTrue(HarnessgramRadioLink.isRadioDeepLink("harnessgram://radio"))
        XCTAssertTrue(HarnessgramRadioLink.isRadioDeepLink("tg://harnessgram/radio?link=x"))
    }

    func testRadioDeepLinkRefusesAnythingElse() {
        let token = "AbCdEfGhIjKlMnOpQrStUvWxYz012345"
        for link in [
            "harnessgram://radio", "harnessgram://radio?link=", "harnessgram://radio?link=http://panel.example.net/listen/\(token)",
            "harnessgram://radio?link=https://panel.example.net/listen/short", "harnessgram://radio?link=https://panel.example.net/radio/live.m3u8",
            "harnessgram://radio?link=https://a.example/listen/\(token)&link=https://b.example/listen/\(token)",
            "harnessgram://other?link=https://panel.example.net/listen/\(token)", "harnessgram://radio/extra?link=https://panel.example.net/listen/\(token)",
            "tg://resolve?domain=x&link=https://panel.example.net/listen/\(token)", "tg://harnessgram/other?link=https://panel.example.net/listen/\(token)",
            "https://radio?link=https://panel.example.net/listen/\(token)", "not a link",
        ] {
            XCTAssertNil(HarnessgramRadioLink.listenLink(fromDeepLink: link), link)
        }
        XCTAssertFalse(HarnessgramRadioLink.isRadioDeepLink("tg://resolve?domain=x"))
        XCTAssertFalse(HarnessgramRadioLink.isRadioDeepLink("https://t.me/x"))
    }

    // Re-review blocker: a link from any chat or site must not silently swap the owner's stream.
    private let token = "AbCdEfGhIjKlMnOpQrStUvWxYz012345"
    private func deepLink(_ listen: String) -> String {
        return "harnessgram://radio?link=" + listen.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }

    func testRadioDeepLinkRefusesAForeignHost() {
        let foreign = "https://evil.example.net/listen/\(self.token)"
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(foreign), currentLink: nil, trustedHost: nil, canPresent: true), .refuse)
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink("https://other.example.test/listen/\(self.token)"), currentLink: nil, trustedHost: nil, canPresent: true), .refuse, "another tailnet (Funnel)")
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink("https://private.example.test.evil.example/listen/\(self.token)"), currentLink: nil, trustedHost: nil, canPresent: true), .refuse, "suffix inside another host")
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(foreign), currentLink: nil, trustedHost: "radio.example.org", canPresent: true), .refuse, "not the trusted host")
        XCTAssertFalse(HarnessgramRadioLink.isAllowedHost(".private.example.test", trustedHost: nil), "the bare suffix is no host")
    }

    func testRadioDeepLinkTakesThePairedOrTrustedHost() {
        let tailnet = "https://mac-mini.private.example.test/listen/\(self.token)"
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(tailnet), currentLink: nil, trustedHost: nil, canPresent: true, pairedOrigin: "https://mac-mini.private.example.test:8443", configuration: HarnessgramLocalConfig()), .save(link: tailnet))
        let trusted = "https://Radio.Example.org/listen/\(self.token)"
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(trusted), currentLink: nil, trustedHost: "radio.example.org", canPresent: true), .save(link: trusted))
    }

    func testRadioDeepLinkAsksBeforeReplacingAnotherLink() {
        let saved = "https://mac-mini.private.example.test/listen/\(self.token)"
        let other = "https://mac-mini.private.example.test/listen/ZyXwVuTsRqPoNmLkJiHgFeDcBa987654"
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(other), currentLink: saved, trustedHost: "mac-mini.private.example.test", canPresent: true), .confirmReplace(link: other, host: "mac-mini.private.example.test"))
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(saved + "/live.m3u8"), currentLink: saved, trustedHost: "mac-mini.private.example.test", canPresent: true), .unchanged, "the same stream")
    }

    func testMissingHostFailsClosedAndConfiguredHostsMatchExactly() {
        let empty = HarnessgramLocalConfig()
        let listen = "https://bridge.example.test/listen/\(self.token)"
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(listen), currentLink: nil, trustedHost: nil, canPresent: true, configuration: empty), .refuse)
        XCTAssertFalse(HarnessgramRadioLink.isAllowedHost("bridge.example.test", trustedHost: nil, pairedOrigin: "http://bridge.example.test", configuration: empty))
        let configured = HarnessgramLocalConfig(bridgeOrigin: "https://bridge.example.test:8443")
        XCTAssertTrue(HarnessgramRadioLink.isAllowedHost("bridge.example.test", trustedHost: nil, configuration: configured))
        XCTAssertFalse(HarnessgramRadioLink.isAllowedHost("bridge.example.test.evil.test", trustedHost: nil, configuration: configured))
        XCTAssertNil(HarnessgramHomeRelay.configuredHost(empty))
        XCTAssertEqual(HarnessgramHomeRelay.configuredHost(HarnessgramLocalConfig(relayHost: "relay.example.test")), "relay.example.test")
        for host in ["", "relay.example.test/path", "user@relay.example.test", "relay.example.test:1080", "relay.example.test?x=1"] {
            XCTAssertNil(HarnessgramHomeRelay.configuredHost(HarnessgramLocalConfig(relayHost: host)))
        }
        XCTAssertTrue(HarnessgramRadioLink.missingHostMessage.contains("לא הוגדרה"))
        XCTAssertTrue(HarnessgramHomeRelay.missingConfigurationMessage.contains("לא הוגדרה"))
    }

    func testLocalConfigurationDefaultsAndMalformedDataContainNoEndpoints() {
        for data in [Data("{}".utf8), Data("not json".utf8), Data(#"{"relayHost": 5}"#.utf8)] {
            let config = HarnessgramLocalConfig.decode(data)
            XCTAssertNil(config.bridgeOrigin)
            XCTAssertNil(config.relayHost)
            XCTAssertNil(config.bridgeBotUsername)
            XCTAssertFalse(config.allowsBridgeOrigin(URL(string: "https://bridge.example.test")!))
        }
        XCTAssertFalse(HarnessgramLocalConfig(bridgeHostSuffixes: [".example.test"]).allowsBridgeOrigin(URL(string: "https://anything.example.test")!), "a broad public suffix is not a private network")
        let privateNetwork = HarnessgramLocalConfig(bridgeHostSuffixes: [".private.example.test"])
        XCTAssertTrue(privateNetwork.allowsBridgeOrigin(URL(string: "https://bridge.private.example.test")!))
        XCTAssertFalse(privateNetwork.allowsBridgeOrigin(URL(string: "https://private.example.test.evil.test")!))
    }

    func testRadioDeepLinkWithoutAScreenIsDropped() {
        let tailnet = "https://mac-mini.private.example.test/listen/\(self.token)"
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(tailnet), currentLink: nil, trustedHost: nil, canPresent: false), .drop)
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision(self.deepLink(tailnet), currentLink: "https://x.private.example.test/listen/\(self.token)", trustedHost: nil, canPresent: false), .drop)
        XCTAssertEqual(HarnessgramRadioLink.deepLinkDecision("https://t.me/x", currentLink: nil, trustedHost: nil, canPresent: false), .notRadioLink)
    }

    /// Build 12 migration (review P2): builds before 12 had no way for the owner to store this key, so an
    /// unmarked stored value, `true` included, is the old default and reads as the new default (off). Only a
    /// write from build 12 on (which always sets the mark) counts as the owner's choice, and it is kept.
    func testAnUnmarkedStoredTrueIsTheOldDefaultAndReadsAsOff() {
        self.withDefaults { defaults in
            defaults.set(true, forKey: HarnessgramSettings.Key.agentQuickActions.rawValue)
            XCTAssertNil(defaults.object(forKey: HarnessgramSettings.Key.agentQuickActionsChosen.rawValue))
            XCTAssertFalse(HarnessgramSettings(defaults: defaults).agentQuickActions, "unmarked true: the build 11 default")
            defaults.set(false, forKey: HarnessgramSettings.Key.agentQuickActions.rawValue)
            XCTAssertFalse(HarnessgramSettings(defaults: defaults).agentQuickActions, "unmarked false: off as well")
            let settings = HarnessgramSettings(defaults: defaults)
            settings.agentQuickActions = true
            XCTAssertEqual(defaults.object(forKey: HarnessgramSettings.Key.agentQuickActionsChosen.rawValue) as? Bool, true, "every write marks a choice")
            XCTAssertTrue(HarnessgramSettings(defaults: defaults).agentQuickActions, "a marked true is kept")
            defaults.set("on", forKey: HarnessgramSettings.Key.agentQuickActions.rawValue)
            XCTAssertFalse(HarnessgramSettings(defaults: defaults).agentQuickActions, "a marked but corrupt value falls back to off")
        }
    }
}
