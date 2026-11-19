import Foundation

/// Rich decisions (owner 19.11, bridge ledger #436): what a decision carries beyond its question, so the native
/// Cockpit can show it whole like the Mini App: pictures, links, longer context, and whether a free comment may be the
/// answer. The bridge's final shape comes from its rich-decisions change; until then every field is optional and a
/// missing or malformed one simply means "none" (never a guess, never an error). Names accepted for each field are
/// listed beside it, so the final schema needs only a test update.
public struct HarnessgramDecisionExtras: Equatable, Sendable {
    public struct Link: Equatable, Sendable {
        public var title: String
        public var url: URL

        public init(title: String, url: URL) {
            self.title = title
            self.url = url
        }
    }

    public static let maxImages = 6
    public static let maxLinks = 8
    public static let contextLimit = 6_000

    /// Card-media ids (32 lowercase hex), fetched through the panel's card-media token. Keys: "images", "media".
    public var imageIds: [String]
    /// HTTPS links only (they open outside the app). Keys: "links" ([{title|label|text, url|href}] or [url]), "link".
    public var links: [Link]
    /// The long context, Hebrew first, paragraph breaks kept. Keys: "context_he", "context", "body_he", "body",
    /// "long_detail_he", "long_detail".
    public var context: String?
    /// The bridge takes a free comment as the whole answer (it approves nothing). Keys: "rich_decision" (true), "comment" (true),
    /// "allow_comment" (true), "answers" containing "comment".
    public var commentAllowed: Bool
    /// The owner's earlier comments on this decision (bridge "replies": [{"at", "text"}]), oldest first, at most 20.
    public var replies: [String]

    public init(imageIds: [String] = [], links: [Link] = [], context: String? = nil, commentAllowed: Bool = false, replies: [String] = []) {
        self.imageIds = imageIds
        self.links = links
        self.context = context
        self.commentAllowed = commentAllowed
        self.replies = replies
    }

    public static let none = HarnessgramDecisionExtras()

    public var isEmpty: Bool {
        return self.imageIds.isEmpty && self.links.isEmpty && self.context == nil
    }

    public static func isMediaId(_ value: String) -> Bool {
        return value.count == 32 && value.allSatisfy { ("0" ... "9").contains($0) || ("a" ... "f").contains($0) }
    }

    public static func parse(_ item: [String: Any]) -> HarnessgramDecisionExtras {
        var extras = HarnessgramDecisionExtras()

        var seenImages = Set<String>()
        for key in ["images", "media"] {
            for case let value as String in (item[key] as? [Any] ?? []) where isMediaId(value) && seenImages.insert(value).inserted {
                if extras.imageIds.count < maxImages {
                    extras.imageIds.append(value)
                }
            }
        }

        var rawLinks: [Any] = item["links"] as? [Any] ?? []
        if let single = item["link"] {
            rawLinks.insert(single, at: 0)
        }
        var seenLinks = Set<String>()
        for raw in rawLinks {
            guard extras.links.count < maxLinks else {
                break
            }
            var urlText: String?
            var titleText: String?
            if let text = raw as? String {
                urlText = text
            } else if let object = raw as? [String: Any] {
                urlText = (object["url"] as? String) ?? (object["href"] as? String)
                titleText = (object["title_he"] as? String) ?? (object["title"] as? String) ?? (object["label"] as? String) ?? (object["text"] as? String)
            }
            guard let urlText, let url = httpsURL(urlText), seenLinks.insert(url.absoluteString).inserted else {
                continue
            }
            let title = HarnessgramCockpitParser.cleanHebrew(titleText, limit: 120)
            extras.links.append(Link(title: title.isEmpty ? (url.host ?? url.absoluteString) : title, url: url))
        }

        for key in ["context_he", "context", "body_he", "body", "long_detail_he", "long_detail"] {
            let text = HarnessgramCockpitParser.cleanHebrew(item[key], limit: contextLimit, multiline: true)
            if !text.isEmpty {
                extras.context = text
                break
            }
        }

        let answers = (item["answers"] as? [Any] ?? []).compactMap { $0 as? String }
        // The bridge marks a decision that takes comments with "rich_decision": true (docs/panel.md).
        extras.commentAllowed = isJSONTrue(item["rich_decision"]) || isJSONTrue(item["comment"]) || isJSONTrue(item["allow_comment"]) || answers.contains("comment")
        for case let reply as [String: Any] in (item["replies"] as? [Any] ?? []) {
            let text = HarnessgramCockpitParser.cleanHebrew(reply["text"], limit: HarnessgramDecisionComment.limit, multiline: true)
            if !text.isEmpty, extras.replies.count < 20 {
                extras.replies.append(text)
            }
        }
        return extras
    }

    /// An absolute https URL with a host and no credentials; anything else is dropped.
    static func httpsURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2_048, let components = URLComponents(string: trimmed), components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else {
            return nil
        }
        return components.url
    }

    /// Exactly the JSON literal `true`.
    static func isJSONTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return false
        }
        return number.boolValue
    }
}
