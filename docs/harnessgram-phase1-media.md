# Harnessgram phase 1: media and intro source changes

## Behavior

`HarnessgramPolicy.media` defaults to `.photos`; choosing a level per chat is a TODO.
`textOnly` keeps ordinary text and basic textual service events. `photos` additionally
permits still photos, still image files and static stickers. `documents` also permits
ordinary file attachments. All three reject videos (including round videos and video
stickers), GIFs, animated stickers, audio, web previews and external embeds.

The policy is deliberately conservative: photos with video representations, composite/
paid attachments, polls, games, widgets, sponsored embeds, rich-message pages and media-bearing service
actions are hidden as a whole. A blocked bubble shows **Media hidden** and retains its
plain caption. Mixed albums retain the separate allowed photo messages. Rich-text and
custom-emoji formatting is reduced to the ordinary text fallback to avoid cached assets.

## Gated paths

| Boundary | Source location |
| --- | --- |
| Policy and resource classification | `submodules/TelegramCore/Sources/HarnessgramPolicy.swift:1` |
| Bubble versus sticker/animated emoji selection | `submodules/TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageItemImpl.swift:391` |
| Bubble content selection, albums, captions and pending edits | `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift:165` |
| Plain placeholder layout (reuses the restricted-message text node) | `submodules/TelegramUI/Components/Chat/ChatMessageRestrictedBubbleContentNode/Sources/ChatMessageRestrictedBubbleContentNode.swift:79` |
| Reply thumbnails, including cached files | `submodules/TelegramUI/Components/Chat/ChatMessageReplyInfoNode/Sources/ChatMessageReplyInfoNode.swift:669` |
| Inline custom emoji fallback | `submodules/TelegramUI/Components/Chat/ChatMessageTextBubbleContentNode/Sources/ChatMessageTextBubbleContentNode.swift:435` |
| Automatic full downloads | `submodules/TelegramUIPreferences/Sources/MediaAutoDownloadSettings.swift:568` |
| Automatic partial downloads | `submodules/TelegramUIPreferences/Sources/MediaAutoDownloadSettings.swift:608` |
| In-chat directional prefetch | `submodules/TelegramUI/Sources/InChatPrefetchManager.swift:60` |
| Interactive and queued downloads | `submodules/FetchManagerImpl/Sources/FetchManagerImpl.swift:776` |
| Video preloading before frame source construction | `submodules/MediaPlayer/Sources/TimeBasedVideoPreload.swift:13` |
| Typed resource fetching, before touching MediaBox | `submodules/TelegramCore/Sources/Network/FetchedMediaResource.swift:124` |
| Direct/streaming MediaBox fallback classifier | `submodules/TelegramCore/Sources/Network/FetchedMediaResource.swift:30` |
| Main account boundary, before auxiliary fetch handlers | `submodules/TelegramCore/Sources/Account/Account.swift:1777` |
| Supplementary account boundary | `submodules/TelegramCore/Sources/Account/Account.swift:1904` |
| Opening cached message media | `submodules/TelegramUI/Sources/OpenChatMessage.swift:33` |
| Adjacent entries in message galleries | `submodules/GalleryUI/Sources/GalleryController.swift:67` |
| Notification attachment fetch and cached attachment delivery | `Telegram/NotificationService/Sources/NotificationService.swift:1550` |
| Policy regression cases | `submodules/TelegramCore/Tests/HarnessgramPolicyTests.swift:42` |

Resource requests retain their parent media classification: a web-page image is not a
photo attachment. Allowed files are restricted to the main file and still previews,
excluding separate sticker premium-video effects. The account boundary also rejects
opaque message-owned resources and untyped document, video, secret-file and HTTP
resources. It runs before auxiliary fetch handlers for both account setups. History,
message metadata and embedded thumbnail bytes carried inside that metadata still sync;
these are not separate attachment downloads.

## Intro and authentication

- Intro copy: `submodules/RMIntro/Sources/platform/ios/RMIntroViewController.m:210`.
- Placeholder icon: `submodules/RMIntro/Sources/platform/ios/RMIntroViewController.m:319`.
- Intro public header: `submodules/RMIntro/PublicHeaders/RMIntro/RMIntroViewController.h:38`.
- Start button: `submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift:83`.

The RMIntro source overrides its six English titles/descriptions; the splash button and
English app-name login copy say Harnessgram. The OpenGL logo renderer/timer was removed
from the intro, replaced by an accessible **H** label. Its snapshot preserves the old
coordinate contract for the transition to phone entry. The real icon and reviewed Hebrew
localization are TODOs. Generated localization tables were not modified.

Truthful references to Telegram as the account/network service, support destination,
server-provided terms and Premium remain. The branded login copies use English fallback
for every interface language; reviewed Hebrew localization is TODO. App-wide icon
catalogs and branding after authentication are outside this intro/login slice.

## Scope limits and build risks

- Avatars, themes, notification sounds and other application chrome are separate from
  message attachments. Known references for them are intentionally preserved.
- Sending, uploads, composer/media-picker previews and non-message profile/search media
  surfaces were not redesigned. Their cached presentation is not covered by this bubble/
  reply/gallery change; typed attachment downloads still pass through the shared gates.
- Classification uses Telegram's media model and MIME metadata. This is a media-kind
  switch, not inspection or moderation of image contents.
- The conservative fallback can deny a legitimate download whose caller drops its media
  reference. Do not bypass it with an untyped resource; retain the typed parent reference.
- No dependency/build-graph, signing, bundle identifier or entitlement changes. The RMIntro
  public header no longer exports the unused GL delegate/timer surface; no callers remain
  in AuthorizationUI or RMIntro. A full build must validate cross-module API/linking.

## Verification

Run `//submodules/TelegramCore:TelegramCoreTests`, then build the simulator and record
labelled frames (see AGENTS.md). Expected frames, before recording:

1. Intro in light/dark: all six pages show neutral Harnessgram copy and a static H, never
   the plane/sphere logo. Start transitions from the H's current position without a jump.
2. Chat in light/dark, cold and warm cache: still photos remain visible at `.photos`;
   videos, round videos, GIFs, video stickers, link previews and embeds show only the
   small placeholder. Captions remain ordinary text. No hidden thumbnail or autoplay frame
   may appear, including during scrolling or editing media.
3. Reply to blocked media, open a photo beside a video, and receive a media notification:
   no hidden thumbnail appears and no hidden attachment fetch starts.
4. Rebuild at `.textOnly`: photo/static-sticker bubbles also become placeholders. Rebuild
   at `.documents`: PDFs become available while motion/audio/embeds remain blocked.
   Observe actual attachment requests/bytes, not only an empty view or download settings.
