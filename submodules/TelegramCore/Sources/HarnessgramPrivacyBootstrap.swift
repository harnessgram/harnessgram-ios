import Postbox
import SwiftSignalKit
internal import TelegramApi

extension HarnessgramPolicy.PrivacyRuleKind {
    init(_ rule: Api.PrivacyRule) {
        switch rule {
        case .privacyValueAllowAll:
            self = .allowAll
        case .privacyValueAllowContacts:
            self = .allowContacts
        case .privacyValueDisallowAll:
            self = .disallowAll
        case .privacyValueDisallowContacts, .privacyValueDisallowUsers, .privacyValueDisallowChatParticipants:
            self = .disallowSome
        default:
            // Particular users or chats, close friends, Premium users, bots and any future rule.
            self = .allowSome
        }
    }
}

/// Re-checked on every launch: only contacts may add the account to groups or call it, and new
/// chats from non-contacts are archived and muted on the server. Anything else is set back. A
/// failed request changes nothing and is retried on the next launch.
func harnessgramEnforceStrangerPrivacy(account: Account) -> Signal<Never, NoError> {
    guard HarnessgramPolicy.contactsOnlyPrivateChats else {
        return .complete()
    }
    let groupInvitations = harnessgramEnforceContactsOnly(account: account, key: .inputPrivacyKeyChatInvite, type: .groupInvitations)
    let calls = harnessgramEnforceContactsOnly(account: account, key: .inputPrivacyKeyPhoneCall, type: .voiceCalls)

    // Writing the global settings sends every field, so the stored copy is refreshed from the
    // server first; if the server cannot be reached, nothing is written (other fields stay intact).
    // Telegram offers archive-and-mute only to some accounts; when a write does not stick, that
    // is logged once and not retried on later launches.
    let accountPeerId = account.peerId
    let strangerChats: Signal<Never, NoError>
    if HarnessgramPolicyStore.shared.isStrangerArchiveUnavailable(accountPeerId: accountPeerId) {
        strangerChats = .complete()
    } else {
        let reachable = account.network.request(Api.functions.account.getGlobalPrivacySettings())
        |> map { _ -> Bool in
            return true
        }
        |> `catch` { _ -> Signal<Bool, NoError> in
            return .single(false)
        }
        let currentSettings = account.postbox.transaction { transaction -> GlobalPrivacySettings in
            return fetchGlobalPrivacySettings(transaction: transaction)
        }
        strangerChats = reachable
        |> mapToSignal { reachable -> Signal<Never, NoError> in
            guard reachable else {
                return .complete()
            }
            return _internal_updateGlobalPrivacySettings(account: account)
            |> then(
                currentSettings
                |> mapToSignal { settings -> Signal<Never, NoError> in
                    if HarnessgramPolicy.archivesStrangerChats(settings) {
                        return .complete()
                    }
                    var settings = settings
                    settings.automaticallyArchiveAndMuteNonContacts = true
                    settings.keepArchivedUnmuted = true
                    return _internal_updateGlobalPrivacySettings(account: account, settings: settings)
                    |> then(_internal_updateGlobalPrivacySettings(account: account))
                    |> then(
                        currentSettings
                        |> mapToSignal { settings -> Signal<Never, NoError> in
                            if !HarnessgramPolicy.archivesStrangerChats(settings) {
                                Logger.shared.log("Harnessgram", "Archive and mute for non-contacts is not available to this account; not retrying")
                                HarnessgramPolicyStore.shared.markStrangerArchiveUnavailable(accountPeerId: accountPeerId)
                            }
                            return .complete()
                        }
                    )
                }
            )
        }
    }
    return groupInvitations
    |> then(calls)
    |> then(strangerChats)
}

private func harnessgramEnforceContactsOnly(account: Account, key: Api.InputPrivacyKey, type: UpdateSelectiveAccountPrivacySettingsType) -> Signal<Never, NoError> {
    return account.network.request(Api.functions.account.getPrivacy(key: key))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.account.PrivacyRules?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<Never, NoError> in
        guard let result else {
            return .complete()
        }
        let rules: [Api.PrivacyRule]
        switch result {
        case let .privacyRules(data):
            rules = data.rules
        }
        if HarnessgramPolicy.isContactsOnly(rules.map(HarnessgramPolicy.PrivacyRuleKind.init)) {
            return .complete()
        }
        Logger.shared.log("Harnessgram", "Setting \(type) privacy back to contacts only")
        return _internal_updateSelectiveAccountPrivacySettings(account: account, type: type, settings: HarnessgramPolicy.contactsOnlyPrivacy)
        |> ignoreValues
    }
}

/// Feeds the account's local contact list to the synchronous chat gates.
func harnessgramTrackContacts(postbox: Postbox, accountPeerId: PeerId) -> Signal<Never, NoError> {
    return postbox.contactPeerIdsView()
    |> map { view -> Set<PeerId> in
        return view.peerIds
    }
    |> distinctUntilChanged
    |> mapToSignal { peerIds -> Signal<Never, NoError> in
        HarnessgramPolicyStore.shared.updateContacts(accountPeerId: accountPeerId, peerIds: peerIds)
        return .complete()
    }
}
