import Foundation

/// A decision's picture (rich decisions): a short-lived, owner-bound token from `POST /api/card-media-token {"id"}`,
/// then `GET /card-media/<id>?auth=<token>` on the same bridge origin. Only images come back; anything else, a
/// failure or a different origin gives nil (the screen shows a neutral placeholder).
public enum HarnessgramCardMedia {
    public static let maxBytes = 4_000_000

    public static func tokenBody(id: String) -> Data? {
        guard HarnessgramDecisionExtras.isMediaId(id) else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: ["id": id])
    }

    /// The image request on the login's own origin; nil for a malformed id or token.
    public static func imageRequest(origin: URL, id: String, token: String) -> URLRequest? {
        guard HarnessgramDecisionExtras.isMediaId(id), !token.isEmpty, token.count <= 512, token.allSatisfy({ $0.isASCII && !$0.isWhitespace }), var components = URLComponents(url: origin, resolvingAgainstBaseURL: false), components.scheme?.lowercased() == "https" else {
            return nil
        }
        components.path = "/card-media/" + id
        components.queryItems = [URLQueryItem(name: "auth", value: token)]
        guard let url = components.url else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 25)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        return request
    }

    /// The token from the bridge's answer, or nil.
    public static func token(from body: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let token = object["token"] as? String, !token.isEmpty, token.count <= 512 else {
            return nil
        }
        return token
    }

    /// Whether the bytes look like an image the app can show (PNG, JPEG, GIF, WebP, HEIC) and are within the size cap.
    public static func looksLikeImage(_ data: Data) -> Bool {
        guard data.count > 12, data.count <= maxBytes else {
            return false
        }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) || bytes.starts(with: [0xFF, 0xD8, 0xFF]) || bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return true
        }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && Array(bytes[8 ..< 12]) == [0x57, 0x45, 0x42, 0x50] {
            return true
        }
        return Array(bytes[4 ..< 8]) == [0x66, 0x74, 0x79, 0x70]
    }
}

extension HarnessgramCockpitClient {
    /// One picture of a decision, or nil (no fresh login, refused, not an image).
    public func cardImage(id: String, credential: HarnessgramCockpitCredential, now: Date) async -> Data? {
        guard credential.canRead(now: now), let origin = credential.originURL, let body = HarnessgramCardMedia.tokenBody(id: id), let tokenRequest = HarnessgramCockpitClient.request(origin: origin, path: HarnessgramCockpitClient.cardMediaTokenPath, credential: credential, body: body) else {
            return nil
        }
        guard let tokenResponse = try? await self.transport.perform(tokenRequest), tokenResponse.status == 200, let token = HarnessgramCardMedia.token(from: tokenResponse.body), let imageRequest = HarnessgramCardMedia.imageRequest(origin: origin, id: id, token: token) else {
            return nil
        }
        guard let imageResponse = try? await self.transport.perform(imageRequest), imageResponse.status == 200, HarnessgramCardMedia.looksLikeImage(imageResponse.body) else {
            return nil
        }
        return imageResponse.body
    }
}
