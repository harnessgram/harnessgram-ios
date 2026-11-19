import Foundation

/// One answer from the bridge: the status, the body and how long it asked the app to wait, when it did.
public struct HarnessgramCockpitHTTPResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data
    /// From `Retry-After` (seconds or an HTTP date) or the body's `"retry"` (seconds), clamped; nil when absent.
    public var retryAfter: TimeInterval?

    public init(status: Int, body: Data, retryAfter: TimeInterval? = nil) {
        self.status = status
        self.body = body
        self.retryAfter = retryAfter
    }
}

/// How the Cockpit client reaches the bridge. The app uses `HarnessgramCockpitURLSessionTransport` (no cookies, no
/// cache, no redirects); tests pass a fake that records requests and answers from a script.
public protocol HarnessgramCockpitTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> HarnessgramCockpitHTTPResponse
    /// Returns nil if authorization was withdrawn before the request started.
    @MainActor
    func perform(_ request: URLRequest, ifAllowed: @MainActor () -> Bool) async throws -> HarnessgramCockpitHTTPResponse?
}

extension HarnessgramCockpitTransport {
    @MainActor
    public func perform(_ request: URLRequest, ifAllowed: @MainActor () -> Bool) async throws -> HarnessgramCockpitHTTPResponse? {
        guard ifAllowed() else { return nil }
        return try await self.perform(request)
    }
}

public struct HarnessgramCockpitURLSessionTransport: HarnessgramCockpitTransport {
    /// Larger answers are refused rather than parsed.
    public static let maxBody = 4_000_000

    let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func perform(_ request: URLRequest) async throws -> HarnessgramCockpitHTTPResponse {
        let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            self.start(request) { continuation.resume(with: $0) }
        }
        return try Self.decode(data, response)
    }

    @MainActor
    public func perform(_ request: URLRequest, ifAllowed: @MainActor () -> Bool) async throws -> HarnessgramCockpitHTTPResponse? {
        let reply: (Data, URLResponse)? = try await withCheckedThrowingContinuation { continuation in
            // Check and resume the data task in the same MainActor turn.
            guard ifAllowed() else {
                continuation.resume(returning: nil)
                return
            }
            self.start(request) { continuation.resume(with: $0.map(Optional.some)) }
        }
        guard let (data, response) = reply else { return nil }
        return try Self.decode(data, response)
    }

    private func start(_ request: URLRequest, completion: @escaping @Sendable (Result<(Data, URLResponse), Error>) -> Void) {
        let task = self.session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
            } else if let data, let response {
                completion(.success((data, response)))
            } else {
                completion(.failure(HarnessgramCockpitClient.FetchError.unavailable))
            }
        }
        task.resume()
    }

    private static func decode(_ data: Data, _ response: URLResponse) throws -> HarnessgramCockpitHTTPResponse {
        guard let http = response as? HTTPURLResponse, data.count <= HarnessgramCockpitURLSessionTransport.maxBody else {
            throw HarnessgramCockpitClient.FetchError.unavailable
        }
        let hasRetryBody = http.statusCode == 409 || http.statusCode == 429 || http.statusCode == 503
        let retryAfter = HarnessgramCockpitPollSchedule.retryAfter(header: http.value(forHTTPHeaderField: "Retry-After"), body: hasRetryBody ? data : nil, now: Date())
        return HarnessgramCockpitHTTPResponse(status: http.statusCode, body: data, retryAfter: retryAfter)
    }
}

/// When the next read of a visible native Cockpit screen may go: every `base` seconds while reads succeed, doubling
/// after each failure up to `maxBackoff`, and never before a time the bridge asked for (`Retry-After`).
public struct HarnessgramCockpitPollSchedule: Equatable, Sendable {
    public static let defaultBase: TimeInterval = 45.0
    public static let maxBackoff: TimeInterval = 600.0
    /// A longer wait than this from the bridge is taken as this.
    public static let maxRetryAfter: TimeInterval = 3600.0

    public let base: TimeInterval
    public private(set) var failures: Int = 0
    /// Nothing is asked before this (the bridge's Retry-After).
    public private(set) var notBefore: Date?

    public init(base: TimeInterval = HarnessgramCockpitPollSchedule.defaultBase) {
        self.base = max(15.0, base)
    }

    public mutating func noteSuccess() {
        self.failures = 0
        self.notBefore = nil
    }

    public mutating func noteFailure(now: Date, retryAfter: TimeInterval?) {
        self.failures = min(self.failures + 1, 16)
        if let retryAfter {
            let until = now.addingTimeInterval(min(max(1.0, retryAfter), HarnessgramCockpitPollSchedule.maxRetryAfter))
            self.notBefore = max(self.notBefore ?? until, until)
        }
    }

    /// Seconds until the next read; `base` overrides the schedule's own interval (a screen that polls more slowly).
    public func delay(now: Date, base: TimeInterval? = nil) -> TimeInterval {
        let base = max(15.0, base ?? self.base)
        var delay = base
        if self.failures > 0 {
            delay = min(base * pow(2.0, Double(self.failures)), max(base, HarnessgramCockpitPollSchedule.maxBackoff))
        }
        if let notBefore = self.notBefore {
            delay = max(delay, notBefore.timeIntervalSince(now))
        }
        return delay
    }

    /// Whether a read (also one the owner asked for) may go now: false while the bridge's Retry-After runs.
    public func mayRequest(now: Date) -> Bool {
        guard let notBefore = self.notBefore else {
            return true
        }
        return now >= notBefore
    }

    /// The wait the bridge asked for: `Retry-After` as seconds or an HTTP date, else the JSON body's `"retry"` seconds.
    public static func retryAfter(header: String?, body: Data?, now: Date) -> TimeInterval? {
        if let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty {
            if header.allSatisfy({ $0.isASCII && $0.isNumber }), let seconds = Double(header) {
                return clamp(seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: header) {
                return clamp(date.timeIntervalSince(now))
            }
        }
        if let body, let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let number = root["retry"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite {
            return clamp(number.doubleValue)
        }
        return nil
    }

    private static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        return min(max(1.0, seconds), maxRetryAfter)
    }
}
