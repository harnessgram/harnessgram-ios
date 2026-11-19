# Harnessgram phase 1: forced sensitive-content filter (slice 4)

## Behavior and server semantics

`HarnessgramPolicy.forceSensitiveFilter` is `true`. A sensitive or porn restriction
on a message or its conversation peer hides the media even if the restriction names
another platform. This decision ignores server allow/ignore settings and age verification.
Other restriction reasons retain their existing behavior. Sensitive bubbles reuse
**Media hidden**; ordinary sensitive-message captions remain text.

Telegram's `sensitiveContentEnabled = true` means **disable filtering**. Both the public
configuration getters and the remote setter enforce `false`. The Data and Storage
switch is omitted and its callback is guarded; the in-chat age/reveal callback also
returns without revealing or changing account settings. The pre-existing settings
search entry is already invisible and cannot expose the guarded row.

Once per main-account initialization (new login and existing account startup), a managed,
account-lifetime operation reads the server capability and requests
`account.setContentSettings(flags: 0)` if `canAdjustSensitiveContent` is set. There is
no polling/retry loop added. API refusal, lack of capability or a failed read leaves
local enforcement active. This sandbox did not contact or update any server.

## Download and cache boundary

A full `MessageReference(message)` captures the message/peer sensitive verdict. Postbox
persists it under an optional `hg.sc` key; missing/legacy, explicitly partial and
FlatBuffer-only references have an unknown verdict and fail closed. No FlatBuffer schema
or generated code is changed. Reconstruct a reference from the complete current message
instead of downgrading it to an untyped reference to restore a legitimate download.

The shared reference/resource policy applies before interactive fetching, gallery
opening and account resource handlers. Both main and supplementary account fetch
boundaries also resolve the latest Postbox message and conversation peer before starting
either an auxiliary or normal fetch; a stale safe verdict cannot override updated
restrictions, and missing records fail closed. PhotoResources checks sensitivity before reading
cached bytes or inline thumbnails, and the direct image cache checks the parent message.
Chat-list preview construction and both profile media grids also reject sensitive
thumbnails, including stored thumbnails. A rebound legacy grid cell disposes its old
loader and clears its previous image. In-chat prefetch excludes sensitive messages.

Notification attachments have no trustworthy parent restriction verdict, so all such
attachments are suppressed while the force switch is enabled. Notification text remains.
Untyped cloud-photo fetches are denied; typed avatar/application references retain their
existing policy. Incoming message metadata can still carry inline thumbnail bytes; the
display guards do not decode/display them for a sensitive message.

## Gated paths (file:line)

| Boundary | Source |
| --- | --- |
| Switch, hidden media and reference/resource policy | `submodules/TelegramCore/Sources/HarnessgramPolicy.swift:77` |
| Effective ignored reasons, setting reads and server writes | `submodules/TelegramCore/Sources/Settings/ContentSettings.swift:9` |
| One server-filter attempt and capability check | `submodules/TelegramCore/Sources/Settings/ContentSettings.swift:115` |
| Main-account lifecycle | `submodules/TelegramCore/Sources/Account/Account.swift:1509` |
| All-platform sensitive/porn classification | `submodules/TelegramCore/Sources/Utils/PeerUtils.swift:19` |
| Message reference propagation and optional persistence | `submodules/TelegramCore/Sources/SyncCore/SyncCore_MediaReference.swift:6` |
| Data and Storage row and action | `submodules/SettingsUI/Sources/Data and Storage/DataAndStorageSettingsController.swift:644`, `:888` |
| In-chat age/reveal bypass | `submodules/TelegramUI/Sources/ChatController.swift:5626` |
| Bubble selection | `submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift:165` |
| Media hidden placeholder | `submodules/TelegramUI/Components/Chat/ChatMessageRestrictedBubbleContentNode/Sources/ChatMessageRestrictedBubbleContentNode.swift:88` |
| Chat list, including secret-photo preview path | `submodules/ChatListUI/Sources/Node/ChatListItem.swift:3298` |
| Photo/file/video cached bytes, thumbnails and snippets | `submodules/PhotoResources/Sources/PhotoResources.swift:64`, `:279`, `:353`, `:533`, `:1045`, `:2050`, `:2270`, `:2653` |
| Direct image cache | `submodules/DirectMediaImageCache/Sources/DirectMediaImageCache.swift:422` |
| New profile grid and cached thumbnails | `submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/MediaGridPaneDataSource.swift:22`, `:264` |
| Legacy profile grid, including reused cells | `submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoVisualMediaPaneNode.swift:960` |
| In-chat prefetch | `submodules/TelegramUI/Sources/InChatPrefetchManager.swift:60` |
| Typed resource and account fetch classifier | `submodules/TelegramCore/Sources/Network/FetchedMediaResource.swift:30`, `:71`, `:160` |
| Notification attachment suppression | `Telegram/NotificationService/Sources/NotificationService.swift:1550` |
| Current message/peer check before auxiliary and normal fetch | `submodules/TelegramCore/Sources/Account/Account.swift:1790`, `:1919` |
| Regression cases, including stale safe references | `submodules/TelegramCore/Tests/HarnessgramPolicyTests.swift:202`, `:260` |

Existing slice-2 consumers gain the sensitive decision through the shared policy:
`OpenChatMessage.swift:33`, `GalleryController.swift:67`, `ChatMessageItemImpl.swift:392`,
`ChatMessageReplyInfoNode.swift:669`, and the interactive/resource fetch gates. See
[harnessgram-phase1-media.md](harnessgram-phase1-media.md) for their full paths.

## Risks and validation limits

- This enforces Telegram's supplied restriction metadata; it does not inspect or classify
  image contents. Unflagged material is outside this classifier's ability.
- Conservative handling also blocks safe media when a caller only has a legacy/partial
  reference (including the background prefetch manager's peer/id-only references).
  FlatBuffer round-trips intentionally lose the local verdict and require a full message.
- Suppressing all notification attachments and untyped photo fetches is deliberate;
  verify ordinary typed photos and typed avatars during the app test.
- The latest-message check runs before a resource transfer starts. It does not retroactively
  cancel a transfer already running before a new restriction arrives or purge existing
  cached bytes; rendering guards cover the listed display surfaces.
- The server setting is best effort, account-wide and can affect other Telegram clients.
  Another client can later change it; this app's local decision remains forced.
- No signing, bundle IDs, entitlements, generated localization or build graph changed.

Run `//submodules/TelegramCore:TelegramCoreTests`. Before recording,
the expected visible results are: no sensitive thumbnail/blur at any point; a **Media
hidden** bubble; captions retained as plain text; a tap cannot reveal or start a download;
the settings switch is absent. Check light/dark, cold/warm cache, mixed albums, reply
thumbnails, adjacent gallery items, chat list and both profile-grid modes. Record and
inspect labelled frames per AGENTS.md; verify attachment requests separately. Check a
server that initially allows sensitive content, both server capability values, and an
offline/failed request.
