# Harnessgram Phase 1: approved channels and groups

The application gates channels and groups through an explicit approval policy.

## Approval contract

`Telegram/Harnessgram/approved.json` is bundled with the main application. Its
schema is `{"usernames": [], "peerIds": []}` and both lists are empty by default.
Usernames are case insensitive and may start with `@`. Only active aliases and
the primary username match. IDs are **decimal strings of Postbox's namespaced
`PeerId.toInt64()`**, not bare Telegram numeric IDs or Bot API `-100...` IDs.
Prefer IDs for stable approvals; usernames can be renamed or reassigned.
Missing or malformed bundle data grants no explicit approvals.

The pure decisions live in `HarnessgramPolicy.swift`. Current membership, cached
peers, contacts, chat history and a pending request do not themselves approve a
group/channel. Private conversations retain the earlier policy.

`HarnessgramPolicyStore` persists one state per account peer ID in application
UserDefaults. Startup captures only locally listed current members, including
archived dialogs, before the account's managers start. A one-time full server
sweep then includes members absent from the local cache at fresh login. It uses
the existing `fetchChatList` pagination/retry implementation for root and archive,
caches cursor peers, and does not import messages or rewrite dialog inclusion.
The persistent completion marker closes enrollment, even for an empty result.
Later membership changes cannot extend a completed snapshot. Corrupt state fails
closed and never reopens enrollment. Lists/search refresh after enrollment.

The remote snapshot is necessarily the first **successful initial synchronization**,
not an atomic server snapshot at the wall-clock instant of launch. Until it
completes, uncached members stay hidden; interruption leaves enrollment pending
for the next startup. External membership changes during that initial sweep can
be included. No subsequent completed-launch sweep runs.

## Gated paths

Paths are relative to the repository root; line references identify each gate.

| Boundary | Gate |
| --- | --- |
| Pure group/channel approval | `submodules/TelegramCore/Sources/HarnessgramPolicy.swift:49` |
| Local enrollment and full initial server sweep | `submodules/TelegramCore/Sources/Account/Account.swift:1330`, `:1508`; `submodules/TelegramCore/Sources/HarnessgramMembershipBootstrap.swift:6` |
| Main/archive items, archive previews, promotional items | `submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift:696`, `:714`, `:726` |
| Engine peer lists | `submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift:600` |
| Forum/synthetic list rows and found peers | `submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift:619`, `:684` |
| Recent search, peer/topic/message/media search results | `submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift:1530`, `:3904` |
| Navigation to peers and reply threads | `submodules/TelegramUI/Sources/NavigateToChatController.swift:24` |
| All direct ChatController constructors, including embedded previews | `submodules/TelegramUI/Sources/ChatController.swift:695` (denied targets become empty custom history before node creation); alert at `:7999` |
| In-place chat and linked-bot-forum switches | `submodules/TelegramUI/Sources/ChatController.swift:11449`, `:11481` |
| Resolved peer/message/thread URLs; invite inspection | `submodules/TelegramUI/Sources/OpenResolvedUrl.swift:120`, `:550` |
| Public channel join and independently checked hash join | `submodules/TelegramCore/Sources/TelegramEngine/Peers/JoinChannel.swift:25` |
| Invite import, including timed-peek joins | `submodules/TelegramCore/Sources/TelegramEngine/Peers/JoinLink.swift:123` |
| Folder invitation and folder-update joins (all selected peers must pass) | `submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatFolders.swift:400`, `:715` |
| Add self to a basic group/channel, singly or in a batch | `submodules/TelegramCore/Sources/TelegramEngine/Peers/AddPeerMember.swift:54`, `:163`, `:280` |
| Paid opaque invite invoice creation, including both payment submission routes | `submodules/TelegramCore/Sources/TelegramEngine/Payments/BotPaymentForm.swift:348` |
| Paid subscription reactivation and rejoin | `submodules/TelegramCore/Sources/TelegramEngine/Payments/Stars.swift:1496`, `:1850`, `:1876`; the actual subscription target is checked separately from the billing-owner peer |

## Local request stub

The existing denial text remains `This chat is not on the approved list`.
An identified denied chat offers `Ask to approve`, records ID/title/time, then
shows the requested `Request sent` text. That text means **saved locally only**
in Phase 1. Requests survive restart, deduplicate per account/target and never
grant approval. `HarnessgramPolicyStore.pendingRequests(accountPeerId:)` is the
single read API for Phase 2 delivery; its TODO requires bridge transport and
acknowledgement. Unknown invitation targets use a domain-separated SHA-256
fingerprint rather than storing a private invite bearer token. Invalid or
unresolvable links have no target for a request action.

## Limits and remaining surfaces

- Opaque private invites (including paid ones) are denied when Telegram does not
  reveal a stable target identity, even if the intended chat might be approved.
  Approved public usernames/IDs and approved identity-bearing peek invites work.
  Whole-folder URLs remain disabled by slice 1; direct engine folder joins are
  additionally guarded here. Cancelling a paid subscription remains allowed.
- Creation (2026-11-17, owner): the owner can always create a group,
  supergroup, channel or community. The new chat is approved at creation by
  the id in the server's answer (`HarnessgramPolicyStore.noteCreatedChat`,
  stored per account next to the grandfathered ids as `createdIds`), before its
  updates reach the chat list. The creator flag never approves a chat: one
  transferred to the owner, an invite link or a join keeps the rules above.
  Media, sticker and link rules inside the new chat are unchanged.
- This is an application access gate, not server-side enforcement. Other
  Telegram clients, incoming external additions, already pending server approval
  requests, bot webview decisions and automatic billing can change membership;
  after enrollment these changes confer no local approval.
- Notifications/extensions, widgets, share/forward pickers, peer-info surfaces,
  call/story/custom-content surfaces and aggregate unread badges are not given a
  blanket allow-list filter by this slice. Raw history/network/cache storage is
  not filtered or erased. Only the enumerated app lists, chat constructors and
  client-initiated membership operations are gated. A release promising universal
  content hiding still needs an audit of those separate surfaces.
- Application UserDefaults is local state, not a tamper-resistant policy store.
  App data removal can restart enrollment. Standard UserDefaults is not a shared
  extension container. A basic-group-to-supergroup migration changes peer ID and
  can require a new explicit approval. Username approvals are mutable; numeric
  IDs are recommended. An ID-only constructor with an unobserved username match
  fails closed until the peer has been checked through navigation/list/search.
- Filtering a fetched list page can leave fewer visible rows than the requested
  page size. Pagination/unread counters retain Telegram's underlying counts.

## Verification

Run `//submodules/TelegramCore:TelegramCoreTests` to verify policy and store regressions.

Before recording UI verification, expect: existing member chats (including old
archived pages) appear after initial enrollment; later externally added groups
stay absent; contacts remain visible; denied links show the denial and request
action; saving a request shows confirmation without revealing chat content;
direct/embedded denied previews contain no original messages. Record these
states in light/dark mode as required by AGENTS.md. Also verify an approved
public join, an unapproved join through each mapped entry point, a mixed folder,
an opaque paid invite, unapproved subscription rejoin/reactivation, and allowed
subscription cancellation. Confirm `approved.json` exists inside the built app.
