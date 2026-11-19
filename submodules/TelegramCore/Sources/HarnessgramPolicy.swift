import Foundation
import Postbox
import HarnessgramSettings
import HarnessgramAgent

/// A resource created on this device: a recording, a camera or library pick, a local file. It is the
/// owner's own content (drafts, recording previews, uploads) and is never filtered.
public protocol HarnessgramDeviceLocalResource {}
extension LocalFileMediaResource: HarnessgramDeviceLocalResource {}
extension LocalFileReferenceMediaResource: HarnessgramDeviceLocalResource {}

public enum HarnessgramPolicy {
    // MARK: The owner's own content

    public static func isDeviceLocal(_ resource: MediaResource) -> Bool {
        return resource is HarnessgramDeviceLocalResource
    }

    /// What the owner sent himself: outgoing, not a forward of someone else's message, not an ad.
    /// It always uploads and shows; the filter applies to what others send.
    public static func isOwnMessage(_ message: EngineMessage) -> Bool {
        return !message._asMessage().flags.contains(.Incoming) && message.forwardInfo == nil && message.adAttribute == nil
    }
    public struct ApprovedChats: Codable, Equatable {
        public let usernames: [String]
        /// Decimal strings of Postbox PeerId.toInt64(), including its namespace.
        public let peerIds: [String]

        public init(usernames: [String] = [], peerIds: [String] = []) {
            self.usernames = usernames
            self.peerIds = peerIds
        }
    }

    public static func normalizedUsername(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.hasPrefix("@") ? String(value.dropFirst()) : value
    }

    /// Deduplicate an unresolved request without persisting a private invite bearer token.
    public static func inviteRequestId(_ hash: String) -> String {
        return "invite:" + hexString(sha256Digest(Data(("HarnessgramInvite:" + hash).utf8)))
    }

    public static func isGroupOrChannel(_ peer: EnginePeer) -> Bool {
        switch peer {
        case .channel, .legacyGroup, .community:
            return true
        case .user, .secretChat:
            return false
        }
    }

    public static func isCurrentMember(_ peer: EnginePeer) -> Bool {
        switch peer {
        case let .channel(channel):
            return channel.participationStatus == .member
        case let .legacyGroup(group):
            return group.membership == .Member
        case let .community(community):
            return community.participationStatus == .member
        case .user, .secretChat:
            return false
        }
    }

    /// Pure decision: current membership is deliberately not an approval source.
    public static func isApprovedGroup(_ peer: EnginePeer, approved: ApprovedChats, grandfatheredIds: Set<Int64>) -> Bool {
        guard isGroupOrChannel(peer) else {
            return false
        }
        let id = peer.id.toInt64()
        if grandfatheredIds.contains(id) || approved.peerIds.contains(String(id)) {
            return true
        }
        var names = peer.usernames.filter { $0.flags.contains(.isActive) }.map { normalizedUsername($0.username) }
        if let name = peer.addressName {
            names.append(normalizedUsername(name))
        }
        let allowedNames = Set(approved.usernames.map(normalizedUsername).filter { !$0.isEmpty })
        return names.contains(where: { allowedNames.contains($0) })
    }

    /// nil means not captured; an empty set is a completed, empty snapshot.
    public static func grandfatheredIds(existing: Set<Int64>?, peers: [EnginePeer]) -> Set<Int64> {
        return existing ?? Set(peers.filter(isCurrentMember).map { $0.id.toInt64() })
    }
    /// Media switch per chat (owner, 2026-11-15: "why hide if it's approved? show everything").
    /// all: every incoming media in an approved chat (photos, videos, GIFs, music, voice, video notes,
    /// documents, polls, locations, contacts); stickers still need an approved pack, link previews an
    /// approved domain, and stories, games, payments and dice stay off.
    public enum MediaLevel: String, Codable, Equatable {
        case textOnly
        case photos
        case documents
        case all
    }

    /// Default for every approved chat; one chat can be tightened (approved.json "mediaLevels" or the store).
    public static let approvedChatMedia: MediaLevel = .all

    public static func strictest(_ a: MediaLevel, _ b: MediaLevel) -> MediaLevel {
        let order: [MediaLevel] = [.textOnly, .photos, .documents, .all]
        return order.firstIndex(of: a)! <= order.firstIndex(of: b)! ? a : b
    }

    /// Fallback when the chat is unknown (a reference without a chat, an unapproved chat): fail closed
    /// to the earlier photos-only rule.
    public static var media: MediaLevel {
        return filterOn(.mediaFilter) ? .photos : .all
    }

    // Build 19: every rule can be switched off in Settings > Harnessgram > "הסינון" (HarnessgramFilterSettings). On, the
    // default, is the filter; off gives Telegram's own behaviour for that rule.
    public static func filterOn(_ rule: HarnessgramFilterRule) -> Bool {
        return HarnessgramFilterSettings.shared.isOn(rule)
    }

    public static var forceSensitiveFilter: Bool {
        return filterOn(.sensitiveContent)
    }
    public static var globalSearch: Bool {
        return !filterOn(.search)
    }
    public static var openUnknownLinks: Bool {
        return !filterOn(.linksOutside)
    }
    /// Rich messages (instant-page bodies) stay hidden behind the media filter.
    public static var hidesRichMessages: Bool {
        return filterOn(.mediaFilter)
    }

    public static var hidesMediaSpoilers: Bool {
        return filterOn(.mediaSpoilers)
    }

    /// Normal attachments use a message attribute. Nested media can carry its own spoiler flag.
    /// The owner's own media and attachments backed entirely by device-local resources are exempt.
    public static func hidesSpoilerMedia(_ message: EngineMessage, enabled: Bool = HarnessgramPolicy.hidesMediaSpoilers) -> Bool {
        guard enabled, !isOwnMessage(message) else {
            return false
        }
        let hasSpoilerAttribute = message.attributes.contains { $0 is MediaSpoilerMessageAttribute }
        return message.media.contains { media in
            return (hasSpoilerAttribute && !isDeviceLocalMedia(media)) || carriesUncheckedSpoiler(media)
        }
    }

    private static func isDeviceLocalMedia(_ media: Media) -> Bool {
        if let file = media as? TelegramMediaFile {
            return isDeviceLocal(file.resource)
                && file.previewRepresentations.allSatisfy { isDeviceLocal($0.resource) }
                && file.videoThumbnails.allSatisfy { isDeviceLocal($0.resource) }
                && (file.videoCover.map { isDeviceLocalMedia($0) } ?? true)
                && file.alternativeRepresentations.allSatisfy { isDeviceLocalMedia($0) }
        }
        if let image = media as? TelegramMediaImage {
            guard !image.representations.isEmpty || !image.videoRepresentations.isEmpty || image.video != nil else {
                return false
            }
            return image.representations.allSatisfy { isDeviceLocal($0.resource) }
                && image.videoRepresentations.allSatisfy { isDeviceLocal($0.resource) }
                && (image.video.map { isDeviceLocalMedia($0) } ?? true)
        }
        return false
    }

    private static func carriesUncheckedSpoiler(_ media: Media) -> Bool {
        switch media {
        case let image as TelegramMediaImage:
            return image.flags.contains(.hasSpoiler) && !isDeviceLocalMedia(image)
        case let file as TelegramMediaFile:
            return file.hasSpoiler && !isDeviceLocalMedia(file)
        case let poll as TelegramMediaPoll:
            return (poll.attachedMedia.map(carriesUncheckedSpoiler) ?? false)
                || poll.options.contains { $0.media.map(carriesUncheckedSpoiler) ?? false }
                || (poll.results.solution.flatMap(\.media).map(carriesUncheckedSpoiler) ?? false)
        case let paid as TelegramMediaPaidContent:
            return paid.extendedMedia.contains(where: extendedMediaCarriesUncheckedSpoiler)
        case let invoice as TelegramMediaInvoice:
            return invoice.extendedMedia.map(extendedMediaCarriesUncheckedSpoiler) ?? false
        default:
            return false
        }
    }

    private static func extendedMediaCarriesUncheckedSpoiler(_ extendedMedia: TelegramExtendedMedia) -> Bool {
        guard case let .full(media) = extendedMedia else {
            return false
        }
        return carriesUncheckedSpoiler(media)
    }

    // Links (slice 7). Web links always leave the app for Safari, where the home filter sees them;
    // nothing web-based is rendered inside the app (no in-app browser, Instant View or embedded players).
    public static var inAppBrowser: Bool {
        return !filterOn(.linksOutside)
    }
    public static var instantView: Bool {
        return !filterOn(.linksOutside)
    }

    /// Lowercased host of an http(s) link; nil for any other scheme or a malformed link.
    public static func webLinkHost(_ url: String) -> String? {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = components.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    /// Link previews show only for approved domains: the domain itself or any of its subdomains,
    /// matched on a label boundary (approving example.org never approves badexample.org).
    public static func isApprovedLinkDomain(_ url: String, domains: [String]) -> Bool {
        guard let host = webLinkHost(url) else {
            return false
        }
        for domain in domains {
            var domain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while domain.hasPrefix(".") || domain.hasPrefix("*") {
                domain.removeFirst()
            }
            if domain.isEmpty {
                continue
            }
            if host == domain || host.hasSuffix("." + domain) {
                return true
            }
        }
        return false
    }

    /// A loaded preview of an approved domain. Story previews and pending previews never show.
    public static func isApprovedLinkPreview(_ webpage: TelegramMediaWebpage, domains: [String]) -> Bool {
        guard case let .Loaded(content) = webpage.content, content.story == nil else {
            return false
        }
        return isApprovedLinkDomain(content.url, domains: domains)
    }

    /// An unapproved link preview is simply left out: the link stays in the text, with no
    /// "Media hidden" placeholder.
    public static func dropsMediaSilently(_ value: EngineMedia, linkPreviews: (TelegramMediaWebpage) -> Bool = HarnessgramPolicyStore.shared.isApprovedLinkPreview) -> Bool {
        if case let .webpage(webpage) = value {
            return !linkPreviews(webpage)
        }
        return false
    }
    /// The owner may always create a group, channel or community, even with the approved-chats rule on
    /// (owner, 2026-11-17: "it should not be filtered"). Creation approves the new chat by its id
    /// (HarnessgramPolicyStore.noteCreatedChat); media, sticker and link rules inside it stay as they are.
    /// Only group, channel and community ids can be approved that way.
    public static func isCreatableChatId(_ peerId: EnginePeer.Id) -> Bool {
        return peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel
    }

    // TODO: Localize through PresentationStrings when Harnessgram strings are generated.
    public static let unapprovedChatText = "This chat is not on the approved list"

    // TODO: Add Hebrew localization together with the other Harnessgram strings.
    public static let hiddenMediaText = "Media hidden"

    // Sticker filter. Search would surface packs nobody approved; GIFs stay under the media switch.
    public static var gifSearch: Bool {
        return !filterOn(.search)
    }
    public static var remoteStickerSearch: Bool {
        return !filterOn(.search)
    }

    // TODO: Localize through PresentationStrings when Harnessgram strings are generated.
    public static let unapprovedStickerText = "This sticker pack is not on the approved list"
    public static let hiddenStickerText = "Sticker hidden. Tap to ask for approval"

    /// Approved sticker/emoji packs. Names are case insensitive short names.
    public struct ApprovedStickerPacks: Codable, Equatable {
        public var ids: Set<Int64>
        public var shortNames: Set<String>

        public init(ids: Set<Int64> = [], shortNames: [String] = []) {
            self.ids = ids
            self.shortNames = Set(shortNames.map(HarnessgramPolicy.normalizedUsername).filter { !$0.isEmpty })
        }

        public func union(_ other: ApprovedStickerPacks) -> ApprovedStickerPacks {
            var result = self
            result.ids.formUnion(other.ids)
            result.shortNames.formUnion(other.shortNames)
            return result
        }
    }

    /// Whether the file is a sticker, custom emoji or animated emoji, and the pack it claims.
    /// A sticker-format file without a pack reference is still a sticker (and unapproved).
    public static func stickerPack(of file: TelegramMediaFile) -> (isSticker: Bool, pack: StickerPackReference?) {
        for attribute in file.attributes {
            switch attribute {
            case let .Sticker(_, packReference, _):
                return (true, packReference)
            case let .CustomEmoji(_, _, _, packReference):
                return (true, packReference)
            default:
                break
            }
        }
        if file.isAnimatedSticker || file.mimeType.lowercased() == "application/x-tgsticker" {
            return (true, nil)
        }
        return (false, nil)
    }

    /// Telegram's own system packs, approved by default. Each is addressed by an official
    /// InputStickerSet type (never by a name), is the same for every account and holds no user content:
    /// - animatedEmoji (inputStickerSetAnimatedEmoji): animated versions of standard emoji.
    /// - animatedEmojiAnimations (inputStickerSetAnimatedEmojiAnimations): their tap effects.
    /// - emojiGenericAnimations (inputStickerSetEmojiGenericAnimations): generic reaction effects.
    /// - iconStatusEmoji (inputStickerSetEmojiDefaultStatuses): default emoji statuses.
    /// - iconChannelStatusEmoji (inputStickerSetEmojiChannelDefaultStatuses): default channel statuses.
    /// - iconTopicEmoji (inputStickerSetEmojiDefaultTopicIcons): default forum topic icons.
    /// Not approved: dice (games of chance), premiumGifts and tonGifts (paid gift art).
    /// Featured or trending packs, even ones published by Telegram, are ordinary packs and need approval.
    public static func isSystemDefaultStickerPack(_ reference: StickerPackReference) -> Bool {
        switch reference {
        case .animatedEmoji, .animatedEmojiAnimations, .emojiGenericAnimations, .iconStatusEmoji, .iconChannelStatusEmoji, .iconTopicEmoji:
            return true
        case .id, .name, .dice, .premiumGifts, .tonGifts:
            return false
        }
    }

    /// Pure decision. Unknown packs are not approved; system defaults are (see isSystemDefaultStickerPack).
    /// Files name their pack by id, so a system pack's concrete id is learned when Telegram answers for it.
    public static func isApprovedStickerPack(_ reference: StickerPackReference?, approved: ApprovedStickerPacks) -> Bool {
        guard let reference else {
            return false
        }
        switch reference {
        case let .id(id, _):
            return approved.ids.contains(id)
        case let .name(name):
            return approved.shortNames.contains(normalizedUsername(name))
        default:
            return isSystemDefaultStickerPack(reference)
        }
    }

    /// Forum topic icons are chrome chosen by the admins of an approved group; they always load.
    /// Only Telegram cloud custom emoji ids (namespace CloudFile) can match.
    /// systemFileIds are files Telegram serves outside any pack list (standard reactions).
    public static func isApprovedSticker(_ file: TelegramMediaFile, approved: ApprovedStickerPacks, topicIconFileIds: Set<Int64>, systemFileIds: Set<Int64> = []) -> Bool {
        if file.fileId.namespace == Namespaces.Media.CloudFile {
            if file.isCustomEmoji && topicIconFileIds.contains(file.fileId.id) {
                return true
            }
            if systemFileIds.contains(file.fileId.id) {
                return true
            }
        }
        return isApprovedStickerPack(stickerPack(of: file).pack, approved: approved)
    }

    /// Pickers (emoji, sticker, mask, reaction, status, topic icon) leave out a group backed by an
    /// unapproved cloud pack, header and panel icon included. Other groups (recent, popular, search
    /// results) mix packs and are filtered item by item.
    public static func pickerShowsPackGroup(_ id: ItemCollectionId, packs: (StickerPackReference) -> Bool) -> Bool {
        switch id.namespace {
        case Namespaces.ItemCollection.CloudStickerPacks, Namespaces.ItemCollection.CloudMaskPacks, Namespaces.ItemCollection.CloudEmojiPacks:
            return packs(.id(id: id.id, accessHash: 0))
        default:
            return true
        }
    }

    /// Request id for the shared approval queue; nil when the pack cannot be named.
    public static func stickerPackRequestId(_ reference: StickerPackReference?) -> String? {
        switch reference {
        case let .id(id, _)?:
            return "stickers:\(id)"
        case let .name(name)?:
            let name = normalizedUsername(name)
            return name.isEmpty ? nil : "stickers:name:" + name
        default:
            return nil
        }
    }

    /// A message that is one standard emoji shows as Telegram's big animated emoji (owner, 2026-11-17: the
    /// bridge's "🧑🏼‍💻" placeholder was blocked). `file` is what the chat resolved for the emoji from the
    /// account's cached animated-emoji set (a skin tone reuses the base file). It shows only when that file
    /// passes the sticker rule, which approves the system sets' files by id (noteSystemStickerPackFiles),
    /// never by a name; custom emoji and several emoji keep the plain text bubble.
    public static func showsLargeAnimatedEmoji(text: String, hasEntities: Bool, file: TelegramMediaFile?, level: MediaLevel, stickers: (TelegramMediaFile) -> Bool = HarnessgramPolicyStore.shared.isApprovedSticker) -> Bool {
        guard text.count == 1, !hasEntities, let file, !file.isCustomEmoji, stickerPack(of: file).isSticker else {
            return false
        }
        return allowsMedia(.file(file), level: level, stickers: stickers)
    }

    /// The first sticker in the message that is hidden by the sticker filter (not by the media level).
    public static func unapprovedSticker(_ message: EngineMessage, stickers: (TelegramMediaFile) -> Bool = HarnessgramPolicyStore.shared.isApprovedSticker) -> (file: TelegramMediaFile, pack: StickerPackReference?)? {
        for media in message.media {
            if let file = media as? TelegramMediaFile {
                let info = stickerPack(of: file)
                if info.isSticker && !stickers(file) {
                    return (file, info.pack)
                }
            }
        }
        return nil
    }

    /// Shared by rendering, interactive downloads and prefetching.
    /// Documents adds ordinary attachments, never video, audio, animations or embeds.
    /// Stickers, custom and animated emoji render only from approved packs, at any non-text level.
    public static func allowsMedia(_ value: EngineMedia, level: MediaLevel = HarnessgramPolicy.media, stickers: (TelegramMediaFile) -> Bool = HarnessgramPolicyStore.shared.isApprovedSticker) -> Bool {
        if carriesUncheckedSpoiler(value._asMedia()) && hidesMediaSpoilers {
            return false
        }
        if !filterOn(.mediaFilter) {
            // The media filter is off: Telegram's own behaviour, except what other rules still keep.
            switch value {
            case let .webpage(webpage):
                return HarnessgramPolicyStore.shared.isApprovedLinkPreview(webpage)
            case let .file(file) where stickerPack(of: file).isSticker:
                return stickers(file)
            case .story:
                return !filterOn(.stories)
            case .widget:
                return !filterOn(.otherBotWidgets)
            default:
                return true
            }
        }
        if case .widget = value {
            // Other bots' widgets: hidden while their rule is on (the bridge's own are let through by allowsBridgeWidget).
            return !filterOn(.otherBotWidgets) && level != .textOnly
        }
        switch value {
        case let .action(action):
            // Keep text-only service messages; photo variants also need the media gate.
            switch action.action {
            case let .photoUpdated(image):
                return image.map({ allowsMedia(.image($0), level: level, stickers: stickers) }) ?? true
            case .groupCreated, .addedMembers, .removedMembers, .titleUpdated, .joinedByLink,
                .channelMigratedFromGroup, .groupMigratedToChannel, .historyCleared, .historyScreenshot,
                .messageAutoremoveTimeoutUpdated, .phoneCall, .peerJoined, .phoneNumberRequest,
                .groupPhoneCall, .inviteToGroupPhoneCall, .joinedByRequest, .joinedChannel:
                return true
            default:
                // Gifts, wallpaper/theme actions and future service payloads can contain media.
                return false
            }
        case let .webpage(webpage):
            // The preview card itself; its photo is checked again at the fetch gate.
            return level != .textOnly && HarnessgramPolicyStore.shared.isApprovedLinkPreview(webpage)
        case let .image(image):
            if level == .all {
                return true
            }
            return level != .textOnly && image.videoRepresentations.isEmpty && image.video == nil
        case let .file(file):
            guard level != .textOnly else {
                return false
            }
            let sticker = stickerPack(of: file)
            if sticker.isSticker {
                // The pack decides for every sticker format; GIFs and videos never reach here.
                return stickers(file)
            }
            if level == .all {
                // Videos, GIFs, music, video notes and any document in an approved chat.
                return true
            }
            if file.isVoice && !file.isInstantVideo && !file.isVideo {
                // Voice notes are speech, not visual media: they play in approved chats.
                return true
            }
            let mimeType = file.mimeType.lowercased()
            guard !file.isVideo && !file.isInstantVideo && !file.isAnimated && !file.isAnimatedSticker && !file.isVideoSticker && !file.isMusic && !file.isVoice,
                !mimeType.hasPrefix("video/"), !mimeType.hasPrefix("audio/"), mimeType != "image/gif", mimeType != "image/apng", mimeType != "application/x-tgsticker" else {
                return false
            }
            if ["image/jpeg", "image/png", "image/heic", "image/heif", "image/webp"].contains(mimeType) {
                return true
            }
            return level == .documents
        case .geo, .contact, .poll, .todo:
            return level == .all
        default:
            // Includes stories, games, dice, payments, widgets and composite/paid media.
            // A nested image must not make an external embed eligible.
            return false
        }
    }

    /// The level automatic download and predownload use. With the Harnessgram switch on and both the
    /// message and the viewing account known, it is the message's own level (its chat's level, held to
    /// a forward's source; unapproved or unknown chats keep the fallback). Otherwise the fallback.
    /// Never looser than the fetch gate for the same message and account; sponsored and sensitive
    /// messages download nothing.
    public static func autoDownloadLevel(message: EngineMessage?, accountPeerId: EnginePeer.Id?, enabled: Bool = HarnessgramSettings.shared.autoDownloadInApprovedChats, levelOf: (EngineMessage, EnginePeer.Id) -> MediaLevel = { HarnessgramPolicyStore.shared.mediaLevel(for: $0, accountPeerId: $1) }) -> MediaLevel {
        if let message, message.adAttribute != nil || isSensitiveContent(message) || hidesSpoilerMedia(message) {
            return .textOnly
        }
        guard let message, let accountPeerId else {
            return media
        }
        // Off: the photos-only fallback, but never looser than the chat's own (possibly tighter) level.
        return strictest(levelOf(message, accountPeerId), enabled ? approvedChatMedia : media)
    }

    /// accountPeerId: the viewing account; nil applies the strictest level across this device's accounts.
    public static func hasHiddenMedia(_ message: EngineMessage, accountPeerId: EnginePeer.Id? = nil) -> Bool {
        return hasHiddenMedia(message, level: HarnessgramPolicyStore.shared.mediaLevel(for: message, accountPeerId: accountPeerId))
    }

    static func hasHiddenMedia(_ message: EngineMessage, level: MediaLevel) -> Bool {
        if isOwnMessage(message) {
            return false
        }
        if hidesSpoilerMedia(message) {
            return true
        }
        let bridgeWidget = level != .textOnly && allowsBridgeWidget(message)
        return isSensitiveContent(message) || message.engineMedia.contains(where: { !allowsMedia($0, level: level) && !dropsMediaSilently($0) && !(bridgeWidget && isWidget($0)) }) || (hidesRichMessages && message.attributes.contains(where: { $0 is RichTextMessageAttribute })) || (message.adAttribute != nil && !sponsoredMedia)
    }

    /// Owner decision (15.11, Cockpit): "Allow the bridge's own interactive widgets (decision buttons) inside
    /// agent groups in Harnessgram, while all other widgets stay blocked by the filter."
    ///
    /// True only for a widget message that (1) is not forwarded, (2) was sent by the bridge bot itself (its user id
    /// is the pinned bridge id, HarnessgramBridgeIdentity; never via another bot), and
    /// (3) sits in the bridge's own agent chats: its private chat with the owner, or a forum group listed as an
    /// agent group (HarnessgramAgentGroups, the same detection as wide bubbles). Everything else keeps
    /// "Media hidden". A chat whose media level is text only still hides it (see `hasHiddenMedia`).
    public static func allowsBridgeWidget(_ message: EngineMessage, agentGroups: HarnessgramAgentGroups = HarnessgramAgentGroups.current(), identity: HarnessgramBridgeIdentity = .shared) -> Bool {
        let raw = message._asMessage()
        guard raw.forwardInfo == nil, raw.media.contains(where: { $0 is TelegramMediaWidget }) else {
            return false
        }
        guard let author = raw.author as? TelegramUser, author.botInfo != nil, HarnessgramAgentChat.isBridgeBot(userId: author.id.id._internalGetInt64Value(), identity: identity) else {
            return false
        }
        if raw.attributes.contains(where: { $0 is InlineBotMessageAttribute }) {
            return false
        }
        let peerId = raw.id.peerId
        if peerId == author.id {
            return true
        }
        guard let channel = raw.peers[peerId] as? TelegramChannel else {
            return false
        }
        let kind = HarnessgramAgentChat.Kind(isBotPrivateChat: false, channelId: channel.id.id._internalGetInt64Value(), isForum: channel.flags.contains(.isForum))
        return HarnessgramAgentChat.isAgentChat(kind, groups: agentGroups)
    }

    public static func isWidget(_ value: EngineMedia) -> Bool {
        if case .widget = value {
            return true
        }
        return false
    }

    public static func isSensitiveRestriction(_ rule: RestrictionRule) -> Bool {
        return rule.reason == "sensitive" || rule.reason == "porn"
    }

    public static func isSensitiveContent(_ message: EngineMessage) -> Bool {
        return forceSensitiveFilter && message._asMessage().isSensitiveContent(platform: "ios", contentSettings: .default)
    }

    /// requestedMediaId: the medium the fetch names. The message's own attachment is not held back by a
    /// separate quote; anything else (unknown, a quote's media, a preview's photo) also passes the quote rule.
    public static func allowsCurrentMessageResourceFetch(_ message: EngineMessage?, peer: EnginePeer?, accountPeerId: EnginePeer.Id? = nil, requestedMediaId: EngineMedia.Id? = nil) -> Bool {
        guard forceSensitiveFilter || hidesMediaSpoilers else {
            return true
        }
        guard let currentMessage = message, !hidesSpoilerMedia(currentMessage) else {
            return false
        }
        guard forceSensitiveFilter else {
            return true
        }
        guard let currentPeer = peer else {
            return false
        }
        let isOwnAttachment = requestedMediaId.map { id in currentMessage._asMessage().media.contains(where: { $0.id == id }) } ?? false
        if !isOwnAttachment && !allowsQuotedMedia(currentMessage, accountPeerId: accountPeerId) {
            // A reply's quoted media belongs to the quote's origin, not to this message.
            return false
        }
        if !isOwnMessage(currentMessage) {
            // The reference only knew the chat; the current message also knows whether it is a forward
            // (held to its source's level) or an outgoing forward of someone else's media.
            let level = HarnessgramPolicyStore.shared.mediaLevel(for: currentMessage, accountPeerId: accountPeerId)
            if currentMessage.engineMedia.contains(where: { !allowsMedia($0, level: level) && !dropsMediaSilently($0) }) {
                return false
            }
        }
        return !isSensitiveContent(currentMessage) && !currentPeer.hasSensitiveContent(platform: "ios", contentSettings: .default)
    }

    /// Media quoted in a reply (QuotedReplyMessageAttribute) is held to the quote's origin: the chat's
    /// level and the quote source's level (unknown source: the fallback). The owner's own replies too.
    public static func allowsQuotedMedia(_ message: EngineMessage, accountPeerId: EnginePeer.Id? = nil, levelOf: (EnginePeer.Id, EnginePeer.Id?) -> MediaLevel = { HarnessgramPolicyStore.shared.mediaLevel(forChatId: $0, accountPeerId: $1) }) -> Bool {
        for attribute in message.attributes {
            guard let quote = attribute as? QuotedReplyMessageAttribute, let media = quote.quote?.media else {
                continue
            }
            let level = strictest(levelOf(message.id.peerId, accountPeerId), quote.peerId.map { levelOf($0, accountPeerId) } ?? HarnessgramPolicy.media)
            if !allowsMedia(EngineMedia(media), level: level) && !dropsMediaSilently(EngineMedia(media)) {
                return false
            }
        }
        return true
    }

    public static func allowsSensitiveMediaReference(_ reference: AnyMediaReference) -> Bool {
        if forceSensitiveFilter, case let .message(message, _) = reference {
            // A legacy/partial reference has no trustworthy message restrictions.
            return message.harnessgramSensitiveContent == false
        }
        return true
    }

    public static func allowsMediaReference(_ reference: AnyMediaReference, accountPeerId: EnginePeer.Id? = nil) -> Bool {
        guard allowsSensitiveMediaReference(reference) else {
            return false
        }
        if case let .message(message, _) = reference, message.harnessgramIsOutgoing == true, message.harnessgramIsForward == false {
            // The owner's own message that is not a forward. An outgoing forward is judged by its
            // source below; a reference that does not know both (saved, legacy) fails closed.
            return true
        }
        switch reference {
        case let .webPage(webPage, media):
            // Only media of an approved domain's preview; the media itself passes the usual checks.
            guard case let .webPage(_, url) = webPage.content, HarnessgramPolicyStore.shared.isApprovedLinkPreviewUrl(url) else {
                return false
            }
            return allowsMedia(EngineMedia(media))
        case .story:
            return false
        case let .avatarList(peer, media):
            return allowsAvatar(of: peer) && allowsMedia(EngineMedia(media))
        case let .message(message, media):
            if let id = media.id, HarnessgramPolicyStore.shared.isUnapprovedWebPreviewMedia(id) {
                return false
            }
            // The chat's own level for the viewing account, held to a forward's source level; a
            // reference that does not know whether it is a forward keeps the fallback.
            return allowsMedia(EngineMedia(media), level: HarnessgramPolicyStore.shared.mediaLevel(for: message, accountPeerId: accountPeerId))
        default:
            // A message-owned reference can name a link preview's photo; it loads only for an approved domain.
            if let id = reference.media.id, HarnessgramPolicyStore.shared.isUnapprovedWebPreviewMedia(id) {
                return false
            }
            return allowsMedia(EngineMedia(reference.media))
        }
    }

    public static func allowsResource(_ reference: MediaResourceReference, accountPeerId: EnginePeer.Id? = nil) -> Bool {
        if isDeviceLocal(reference.resource) {
            return true
        }
        switch reference {
        case let .media(reference, resource):
            guard allowsMediaReference(reference, accountPeerId: accountPeerId) else {
                return false
            }
            let value = EngineMedia(reference.media)
            if case let .image(image) = value {
                // A photo's video part passed allowsMediaReference only where the chat allows all media.
                return image.representations.contains(where: { $0.resource.id == resource.id }) || image.videoRepresentations.contains(where: { $0.resource.id == resource.id })
            }
            if case let .file(file) = value {
                // Static stickers can carry a separate premium video effect; it stays hidden.
                if file.resource.id == resource.id || file.previewRepresentations.contains(where: { $0.resource.id == resource.id }) {
                    return true
                }
                return !stickerPack(of: file).isSticker && file.videoThumbnails.contains(where: { $0.resource.id == resource.id })
            }
            return true
        case .standalone:
            // Message-owned requests without metadata are rejected at the account boundary.
            return true
        case let .stickerPackThumbnail(stickerPack, _):
            return HarnessgramPolicy.media != .textOnly && HarnessgramPolicyStore.shared.isApprovedStickerPack(stickerPack)
        case let .avatar(peer, _), let .avatarList(peer, _):
            return allowsAvatar(of: peer)
        case let .messageAuthorAvatar(message, _):
            if case let .message(_, author, _, _, _, _, _) = message.content, let author {
                return allowsAvatar(of: author)
            }
            // The author is not in the reference; the account boundary re-reads the message and decides.
            return true
        default:
            // Avatars, themes and application chrome are not message attachments.
            return true
        }
    }

    // MARK: Stories and profile photos (slice 9)

    /// Stories are off: no story list, rings, counts or posting; story media never loads.
    public static var stories: Bool {
        return !filterOn(.stories)
    }

    /// Sponsored messages (Telegram API ToS 3.3) keep Telegram's own layout: the "Sponsored" label,
    /// the sponsor button with Telegram's open-link confirmation, hide and report. Their media is
    /// optional per core.telegram.org/api/sponsored-messages and is never shown or prefetched.
    public static var sponsoredMedia: Bool {
        return !filterOn(.adMedia)
    }

    /// Prefetch and automatic download never touch a sponsored message's media.
    public static func allowsPrefetch(_ message: EngineMessage, media: EngineMedia, accountPeerId: EnginePeer.Id? = nil) -> Bool {
        if message.adAttribute != nil && !sponsoredMedia {
            return false
        }
        if isOwnMessage(message) {
            return true
        }
        return !isSensitiveContent(message) && !hidesSpoilerMedia(message) && allowsMedia(media, level: HarnessgramPolicyStore.shared.mediaLevel(for: message, accountPeerId: accountPeerId))
    }

    /// A user's profile photo shows for the account itself, its contacts, and bots the account has a
    /// chat with or that take part in an approved group or channel. Groups and channels keep their
    /// photos (they pass the allow list first). Everyone else shows initials.
    public static func showsProfilePhoto(ofUser id: Int64, contacts: Set<Int64>, accountPeerIds: Set<Int64>, approvedBots: Set<Int64> = []) -> Bool {
        return accountPeerIds.contains(id) || contacts.contains(id) || approvedBots.contains(id)
    }

    /// Avatar fetches name their owner; a user's avatar loads only when its photo shows.
    public static func allowsAvatar(of peer: PeerReference, shows: (EnginePeer.Id) -> Bool = HarnessgramPolicyStore.shared.showsProfilePhoto) -> Bool {
        if case let .user(id, _) = peer {
            return shows(EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id)))
        }
        return true
    }

    // MARK: Strangers (slice 10)

    /// Private chats only with contacts. Others go to the local request list; private chats that
    /// existed when this filter first ran are grandfathered. Bots stay reachable until slice 8.
    public static var contactsOnlyPrivateChats: Bool {
        return filterOn(.contactsOnly)
    }

    /// Telegram's own service account (login codes and security notices).
    public static let telegramServiceUserId: Int64 = 777000

    /// One privacy rule as the server reports it, reduced to what the contacts-only check needs.
    public enum PrivacyRuleKind: Equatable {
        case allowAll
        case allowContacts
        /// Specific users or chats, close friends, Premium users, bots, or an unknown rule.
        case allowSome
        case disallowAll
        case disallowSome
    }

    /// Only contacts may add the account to groups: contacts (or nobody) are allowed, with no
    /// "everybody" and no exception for particular users, chats, Premium users or bots.
    public static func isContactsOnly(_ rules: [PrivacyRuleKind]) -> Bool {
        if rules.contains(.allowAll) || rules.contains(.allowSome) {
            return false
        }
        return rules.contains(.allowContacts) || rules.contains(.disallowAll)
    }

    /// The setting written when the server value is anything else.
    public static let contactsOnlyPrivacy: SelectivePrivacySettings = .enableContacts(enableFor: [:], disableFor: [:], enableForPremium: false, enableForBots: false)

    /// New chats from non-contacts are archived and muted on the server, and stay archived.
    public static func archivesStrangerChats(_ settings: GlobalPrivacySettings) -> Bool {
        return settings.automaticallyArchiveAndMuteNonContacts && settings.keepArchivedUnmuted
    }

    // A cached public peer, current membership or chat history alone is not approval.
    /// A private chat is approved for a contact, a bot, the account itself, Telegram's service
    /// account, an explicitly approved id, or a chat grandfathered when the filter first ran.
    public static func isApprovedPeer(_ peer: EnginePeer, accountPeerId: EnginePeer.Id, hasChat: Bool, isContact: Bool, approved: ApprovedChats = ApprovedChats(), grandfatheredIds: Set<Int64> = [], grandfatheredPrivateIds: Set<Int64> = []) -> Bool {
        if peer.id == accountPeerId {
            return true
        }
        switch peer {
        case .channel, .legacyGroup, .community:
            return isApprovedGroup(peer, approved: approved, grandfatheredIds: grandfatheredIds)
        case let .user(user):
            if isContact || user.botInfo != nil || user.id.id._internalGetInt64Value() == telegramServiceUserId {
                return true
            }
            if !contactsOnlyPrivateChats {
                return hasChat
            }
            if approved.peerIds.contains(String(peer.id.toInt64())) {
                return true
            }
            return hasChat && grandfatheredPrivateIds.contains(peer.id.toInt64())
        case .secretChat:
            if isContact {
                return hasChat
            }
            if !contactsOnlyPrivateChats {
                return hasChat
            }
            return hasChat && grandfatheredPrivateIds.contains(peer.id.toInt64())
        }
    }

    /// Private chats captured on the filter's first run: users and secret chats, nothing else.
    public static func grandfatheredPrivateIds(peers: [EnginePeer]) -> Set<Int64> {
        return Set(peers.filter { peer in
            switch peer {
            case .user, .secretChat:
                return true
            case .channel, .legacyGroup, .community:
                return false
            }
        }.map { $0.id.toInt64() })
    }
}
