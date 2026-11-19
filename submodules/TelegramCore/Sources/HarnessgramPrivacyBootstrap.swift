import Foundation
import HarnessgramSettings
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
        case .privacyValueDisallowContacts, .privacyValueDisallowUsers, .privacyValueDisallowChatParticipants, .privacyValueDisallowBots:
            self = .disallowSome
        default:
            // Particular users or chats, close friends, Premium users, bots and any future rule.
            self = .allowSome
        }
    }
}

func harnessgramRestrictedPrivacyRule(_ rules: [HarnessgramPolicy.PrivacyRuleKind]) -> Api.InputPrivacyRule? {
    guard rules.contains(.allowAll) || rules.contains(.allowSome) else {
        return nil
    }
    // Without an allow-all or allow-contacts baseline, Telegram defaults to Nobody.
    let allowsContacts = rules.contains(.allowAll) || rules.contains(.allowContacts)
    return allowsContacts ? .inputPrivacyValueAllowContacts : .inputPrivacyValueDisallowAll
}

/// Runs a pass when both consent and the contacts-only rule are on, and disposes it when either turns off.
func harnessgramAccountPrivacyBootstrap(
    store: HarnessgramPolicyStore,
    accountId: AccountRecordId,
    apply: @escaping () -> Signal<Never, NoError>
) -> Signal<Never, NoError> {
    let filterChanges = Signal<Void, NoError> { subscriber in
        // Other filter instances can update the same defaults.
        let observer = NotificationCenter.default.addObserver(forName: HarnessgramFilterSettings.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(())
        }
        subscriber.putNext(())
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return combineLatest(store.accountPrivacyConsentUpdates(accountId: accountId), filterChanges)
    |> runOn(.mainQueue())
    |> map { consent, _ in consent == .granted && store.filter.isOn(.contactsOnly) }
    |> distinctUntilChanged
    |> mapToSignal { enabled -> Signal<Never, NoError> in
        guard enabled else {
            return .complete()
        }
        return deferred(apply)
    }
}

func harnessgramEnforceStrangerPrivacy(account: Account) -> Signal<Never, NoError> {
    let store = HarnessgramPolicyStore.shared
    let accountId = account.id
    let accountPeerId = account.peerId
    let network = account.network
    let postbox = account.postbox

    return harnessgramAccountPrivacyBootstrap(store: store, accountId: accountId, apply: {
        // Recheck before writing in case a rule change is still waiting to notify the main queue.
        let canWrite = { store.filter.isOn(.contactsOnly) }
        let privacyTypes: [UpdateSelectiveAccountPrivacySettingsType] = [
            .phoneNumber, .presence, .profilePhoto, .voiceCalls, .groupInvitations
        ]
        let privacy = privacyTypes.reduce(Signal<Never, NoError>.complete()) { previous, type in
            return previous |> then(deferred {
                return harnessgramEnforceContactsOnly(network: network, type: type, canWrite: canWrite)
            })
        }
        return privacy |> then(deferred {
            guard !store.isStrangerArchiveUnavailable(accountPeerId: accountPeerId) else {
                return .complete()
            }
            return harnessgramArchiveStrangerChats(postbox: postbox, network: network, canWrite: canWrite, unavailable: {
                store.markStrangerArchiveUnavailable(accountPeerId: accountPeerId)
            })
        })
    })
}

private func harnessgramEnforceContactsOnly(network: Network, type: UpdateSelectiveAccountPrivacySettingsType, canWrite: @escaping () -> Bool) -> Signal<Never, NoError> {
    return network.request(Api.functions.account.getPrivacy(key: type.apiKey), automaticFloodWait: false)
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.account.PrivacyRules?, NoError> in
        return .single(nil)
    }
    |> deliverOnMainQueue
    |> mapToSignal { result -> Signal<Never, NoError> in
        guard case let .privacyRules(data)? = result else {
            return .complete()
        }
        guard let rule = harnessgramRestrictedPrivacyRule(data.rules.map(HarnessgramPolicy.PrivacyRuleKind.init)), canWrite() else {
            return .complete()
        }
        return network.request(Api.functions.account.setPrivacy(key: type.apiKey, rules: [rule]), automaticFloodWait: false)
        |> `catch` { _ -> Signal<Api.account.PrivacyRules, NoError> in
            return .complete()
        }
        |> deliverOnMainQueue
        |> ignoreValues
    }
}

private func harnessgramArchiveStrangerChats(postbox: Postbox, network: Network, canWrite: @escaping () -> Bool, unavailable: @escaping () -> Void) -> Signal<Never, NoError> {
    let archiveFlags: Int32 = (1 << 0) | (1 << 1)
    return network.request(Api.functions.account.getGlobalPrivacySettings(), automaticFloodWait: false)
    |> `catch` { _ -> Signal<Api.GlobalPrivacySettings, NoError> in
        return .complete()
    }
    |> deliverOnMainQueue
    |> mapToSignal { settings -> Signal<Never, NoError> in
        let proposedSettings: Api.GlobalPrivacySettings
        switch settings {
        case let .globalPrivacySettings(data):
            guard data.flags & archiveFlags != archiveFlags else {
                return storeGlobalPrivacySettings(postbox: postbox, settings: settings)
            }
            // Preserve the other server fields and change only the two disclosed archive options.
            proposedSettings = .globalPrivacySettings(.init(
                flags: data.flags | archiveFlags,
                noncontactPeersPaidStars: data.noncontactPeersPaidStars,
                disallowedGifts: data.disallowedGifts
            ))
        }
        guard canWrite() else {
            return .complete()
        }
        return network.request(Api.functions.account.setGlobalPrivacySettings(settings: proposedSettings), automaticFloodWait: false)
        |> `catch` { _ -> Signal<Api.GlobalPrivacySettings, NoError> in
            return .complete()
        }
        |> deliverOnMainQueue
        |> mapToSignal { updatedSettings -> Signal<Never, NoError> in
            switch updatedSettings {
            case let .globalPrivacySettings(data):
                if data.flags & archiveFlags != archiveFlags {
                    unavailable()
                }
            }
            return storeGlobalPrivacySettings(postbox: postbox, settings: updatedSettings)
        }
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
