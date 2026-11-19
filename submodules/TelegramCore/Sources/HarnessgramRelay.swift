import Foundation
import Network
import Postbox
import SwiftSignalKit
import HarnessgramSettings

/// Harnessgram: Telegram through your configured computer relay when it answers, directly when it does not.
/// The relay is never allowed to leave the app without a connection, and calls never use it.
public enum HarnessgramRelay {
    public static var server: ProxyServerSettings? {
        let server = self.server(configuration: .bundled)
        if let server {
            self.remember(server)
        }
        return server
    }

    /// The last relay this install was configured with. A later build without relay settings uses it to take
    /// that relay out of the stored proxy list, so an unmanaged proxy is never left switched on.
    private static let rememberedKey = "harnessgram.relay.remembered"

    public static var remembered: ProxyServerSettings? {
        guard let value = UserDefaults.standard.string(forKey: self.rememberedKey) else { return nil }
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, let port = Int32(parts[1]), (1 ... 65535).contains(port) else { return nil }
        return ProxyServerSettings(host: parts[0], port: port, connection: .socks5(username: nil, password: nil))
    }

    private static func remember(_ server: ProxyServerSettings) {
        let value = "\(server.host)|\(server.port)"
        if UserDefaults.standard.string(forKey: self.rememberedKey) != value {
            UserDefaults.standard.set(value, forKey: self.rememberedKey)
        }
    }

    public static func server(configuration: HarnessgramLocalConfig) -> ProxyServerSettings? {
        guard let host = HarnessgramHomeRelay.configuredHost(configuration) else { return nil }
        let port = configuration.relayPort ?? 1080
        guard (1 ... 65535).contains(port) else { return nil }
        return ProxyServerSettings(host: host, port: port, connection: .socks5(username: nil, password: nil))
    }

    /// The proxy settings for the switch and the relay's state. With the switch on, the relay is in the
    /// list, calls never use a proxy, and the relay is the active proxy only while `useRelay`; otherwise
    /// it is switched off so Telegram connects directly (another proxy the owner chose is left alone).
    /// With the switch off, an active relay is switched off and nothing else changes.
    /// Without relay settings, a relay remembered from an earlier configured build (`stale`) is switched off
    /// and removed from the list; other proxies are left alone.
    public static func apply(_ settings: ProxySettings, switchOn: Bool, useRelay: Bool, relay: ProxyServerSettings? = HarnessgramRelay.server, stale: ProxyServerSettings? = HarnessgramRelay.remembered) -> ProxySettings {
        guard let relay else {
            guard let stale else { return settings }
            var result = settings
            if result.activeServer == stale {
                result.activeServer = nil
                result.enabled = false
            }
            result.servers.removeAll(where: { $0 == stale })
            return result
        }
        var result = settings
        guard switchOn else {
            if result.activeServer == relay {
                result.enabled = false
            }
            return result
        }
        if !result.servers.contains(relay) {
            result.servers.insert(relay, at: 0)
        }
        result.useForCalls = false
        if useRelay {
            result.activeServer = relay
            result.enabled = true
        } else if result.activeServer == nil || result.activeServer == relay {
            result.enabled = false
        }
        return result
    }

    /// Whether stored settings differ from what the switch and the relay's state require (for example
    /// the relay switched on by hand while it is down, or calls set to use the proxy).
    public static func needsCorrection(_ settings: ProxySettings, switchOn: Bool, useRelay: Bool, relay: ProxyServerSettings? = HarnessgramRelay.server, stale: ProxyServerSettings? = HarnessgramRelay.remembered) -> Bool {
        return self.apply(settings, switchOn: switchOn, useRelay: useRelay, relay: relay, stale: stale) != settings
    }

    /// The fallback state machine. It starts direct; a successful probe moves it to the relay. Two failed
    /// probes within `failureWindow`, or `stuckLimit` seconds of "connecting to proxy", move it back to
    /// direct. A relay that answers probes but does not carry Telegram waits longer each time.
    public struct Monitor: Equatable {
        public enum Mode: Equatable {
            case direct
            case relay
        }

        public static let failureWindow: Double = 5.0
        public static let stuckLimit: Double = 10.0
        public static let probeInterval: Double = 60.0
        public static let maxRetryInterval: Double = 15.0 * 60.0

        public private(set) var mode: Mode = .direct
        public private(set) var retryAfter: Double = 0.0
        private var failureCount: Int = 0
        private var firstFailureAt: Double?
        private var connectingSince: Double?
        private var stuckFallbacks: Int = 0

        public init() {
        }

        public mutating func probe(reachable: Bool, at time: Double) {
            switch self.mode {
            case .direct:
                if reachable && time >= self.retryAfter {
                    self.mode = .relay
                    self.failureCount = 0
                    self.firstFailureAt = nil
                    self.connectingSince = nil
                }
            case .relay:
                if reachable {
                    self.failureCount = 0
                    self.firstFailureAt = nil
                } else {
                    if let first = self.firstFailureAt, time - first <= Monitor.failureWindow {
                        self.failureCount += 1
                    } else {
                        self.firstFailureAt = time
                        self.failureCount = 1
                    }
                    if self.failureCount >= 2 {
                        self.fallBack(retryAfter: time)
                    }
                }
            }
        }

        /// `connectingThroughProxy`: Telegram is trying to connect through a proxy; `online`: connected.
        public mutating func connection(connectingThroughProxy: Bool, online: Bool, at time: Double) {
            guard self.mode == .relay else {
                self.connectingSince = nil
                return
            }
            if connectingThroughProxy {
                if self.connectingSince == nil {
                    self.connectingSince = time
                }
                self.check(at: time)
            } else {
                self.connectingSince = nil
                if online {
                    self.stuckFallbacks = 0
                }
            }
        }

        /// Called regularly, so a connection stuck on the relay falls back even without a new status.
        public mutating func check(at time: Double) {
            if self.mode == .relay, let since = self.connectingSince, time - since > Monitor.stuckLimit {
                self.stuckFallbacks += 1
                let wait = min(Monitor.maxRetryInterval, Monitor.probeInterval * pow(2.0, Double(self.stuckFallbacks - 1)))
                self.fallBack(retryAfter: time + wait)
            }
        }

        public var isWaitingOnRelayConnection: Bool {
            return self.connectingSince != nil
        }

        private mutating func fallBack(retryAfter: Double) {
            self.mode = .direct
            self.retryAfter = retryAfter
            self.failureCount = 0
            self.firstFailureAt = nil
            self.connectingSince = nil
        }
    }
}

/// Runs the relay switch for the whole app: probes the relay over TCP, watches the primary account's
/// connection, and keeps the shared proxy settings in line with `HarnessgramRelay.Monitor`.
public final class HarnessgramRelayController {
    private let queue = Queue(name: "HarnessgramRelay")
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let settings: HarnessgramSettings
    private var monitor = HarnessgramRelay.Monitor()
    private var appliedState: (switchOn: Bool, useRelay: Bool)?
    private var timer: SwiftSignalKit.Timer?
    private var ticks = 0
    private var probing = false
    private var connectionDisposable: Disposable?
    private var proxySettingsDisposable: Disposable?
    private var settingsObserver: NSObjectProtocol?

    public init(accountManager: AccountManager<TelegramAccountManagerTypes>, connectionStatus: Signal<ConnectionStatus?, NoError>, settings: HarnessgramSettings = .shared) {
        self.accountManager = accountManager
        self.settings = settings
        self.queue.async { [weak self] in
            self?.start()
        }
        // Changes made elsewhere (by hand in the proxy screen) are corrected to the switch and relay state.
        self.proxySettingsDisposable = (accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> map { sharedData -> ProxySettings in
            return sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
        }
        |> deliverOn(self.queue)).start(next: { [weak self] stored in
            self?.storedSettingsUpdated(stored)
        })
        self.connectionDisposable = (connectionStatus |> deliverOn(self.queue)).start(next: { [weak self] status in
            self?.connectionUpdated(status)
        })
        self.settingsObserver = NotificationCenter.default.addObserver(forName: HarnessgramSettings.didChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            self?.queue.async {
                self?.applyIfNeeded()
                self?.probe()
            }
        })
    }

    deinit {
        self.connectionDisposable?.dispose()
        self.proxySettingsDisposable?.dispose()
        self.timer?.invalidate()
        if let settingsObserver = self.settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    private func start() {
        self.applyIfNeeded()
        self.probe()
        let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: { [weak self] in
            self?.tick()
        }, queue: self.queue)
        self.timer = timer
        timer.start()
    }

        private var now: Double {
        return CFAbsoluteTimeGetCurrent()
    }

    private func tick() {
        guard self.settings.connectThroughHomeRelay else {
            return
        }
        self.monitor.check(at: self.now)
        self.applyIfNeeded()
        self.ticks += 1
        // Every minute; while waiting on a relay connection, every few seconds.
        if self.ticks * 2 >= Int(HarnessgramRelay.Monitor.probeInterval) || (self.monitor.isWaitingOnRelayConnection && self.ticks % 2 == 0) {
            self.ticks = 0
            self.probe()
        }
    }

    private func connectionUpdated(_ status: ConnectionStatus?) {
        guard self.settings.connectThroughHomeRelay else {
            return
        }
        var connectingThroughProxy = false
        var online = false
        switch status {
        case let .connecting(proxyAddress, _)?:
            connectingThroughProxy = proxyAddress != nil
        case .online?, .updating?:
            online = true
        case .waitingForNetwork?, nil:
            break
        }
        let wasWaiting = self.monitor.isWaitingOnRelayConnection
        self.monitor.connection(connectingThroughProxy: connectingThroughProxy, online: online, at: self.now)
        self.applyIfNeeded()
        if self.monitor.isWaitingOnRelayConnection && !wasWaiting {
            self.probe()
        }
    }

    private func probe() {
        guard self.settings.connectThroughHomeRelay, let relay = HarnessgramRelay.server, !self.probing else {
            return
        }
        self.probing = true
        let connection = NWConnection(host: NWEndpoint.Host(relay.host), port: NWEndpoint.Port(rawValue: UInt16(relay.port))!, using: .tcp)
        var finished = false
        let finish: (Bool) -> Void = { [weak self] reachable in
            guard let self, !finished else {
                return
            }
            finished = true
            connection.cancel()
            self.probing = false
            let wasRelay = self.monitor.mode == .relay
            self.monitor.probe(reachable: reachable, at: self.now)
            self.applyIfNeeded()
            if !reachable && wasRelay && self.monitor.mode == .relay {
                // One failure: confirm within the failure window.
                self.queue.after(2.5, { [weak self] in
                    self?.probe()
                })
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            self?.queue.async {
                switch state {
                case .ready:
                    finish(true)
                case .failed, .waiting, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
        }
        connection.start(queue: self.queue.queue)
        self.queue.after(2.0, {
            finish(false)
        })
    }

    private func storedSettingsUpdated(_ stored: ProxySettings) {
        let switchOn = self.settings.connectThroughHomeRelay
        let useRelay = switchOn && self.monitor.mode == .relay
        if switchOn && HarnessgramRelay.needsCorrection(stored, switchOn: switchOn, useRelay: useRelay) {
            self.appliedState = nil
            self.applyIfNeeded()
        }
    }

    private func applyIfNeeded() {
        let switchOn = self.settings.connectThroughHomeRelay
        let useRelay = switchOn && self.monitor.mode == .relay
        if let applied = self.appliedState, applied.switchOn == switchOn, applied.useRelay == useRelay {
            return
        }
        if !switchOn {
            self.monitor = HarnessgramRelay.Monitor()
        }
        self.appliedState = (switchOn, useRelay)
        let _ = updateProxySettingsInteractively(accountManager: self.accountManager, { current in
            return HarnessgramRelay.apply(current, switchOn: switchOn, useRelay: useRelay)
        }).start()
    }
}
