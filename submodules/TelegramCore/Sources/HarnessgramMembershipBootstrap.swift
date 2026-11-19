import Postbox
import SwiftSignalKit

/// One full initial dialog sweep, using Telegram's existing pagination/retry path.
/// It does not import messages, reset state, join chats or broaden later membership.
func harnessgramCaptureInitialMembership(postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<Never, NoError> {
    return postbox.transaction { _ -> Bool in
        return HarnessgramPolicyStore.shared.needsServerSnapshot(accountPeerId: accountPeerId)
    }
    |> mapToSignal { needed -> Signal<Never, NoError> in
        guard needed else {
            return .complete()
        }
        return harnessgramMembershipPage(postbox: postbox, network: network, accountPeerId: accountPeerId, location: .general, upperBound: .absoluteUpperBound(), collected: [])
        |> mapToSignal { peers -> Signal<[EnginePeer], NoError> in
            return harnessgramMembershipPage(postbox: postbox, network: network, accountPeerId: accountPeerId, location: .group(Namespaces.PeerGroup.archive), upperBound: .absoluteUpperBound(), collected: peers)
        }
        |> map { peers -> Void in
            HarnessgramPolicyStore.shared.completeInitialMembership(peers: peers, accountPeerId: accountPeerId)
        }
        |> ignoreValues
    }
}

private func harnessgramMembershipPage(postbox: Postbox, network: Network, accountPeerId: PeerId, location: FetchChatListLocation, upperBound: MessageIndex, collected: [EnginePeer]) -> Signal<[EnginePeer], NoError> {
    return fetchChatList(accountPeerId: accountPeerId, postbox: postbox, network: network, location: location, upperBound: upperBound, hash: 0, limit: 100)
    |> mapToSignal { page -> Signal<[EnginePeer], NoError> in
        guard let page else {
            // Never finalize an incomplete/unknown snapshot as an empty successful one.
            return .complete()
        }
        let peers = collected + page.chatPeerIds.compactMap { page.peers.get($0).map(EnginePeer.init) }
        guard let next = page.lowerNonPinnedIndex else {
            return .single(peers)
        }
        guard next < upperBound else {
            return .complete()
        }
        // The existing fetcher resolves the next cursor from Postbox. Cache peers only;
        // do not write dialog inclusion or history as part of this policy bootstrap.
        return postbox.transaction { transaction -> Void in
            updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: page.peers)
        }
        |> mapToSignal { _ -> Signal<[EnginePeer], NoError> in
            return harnessgramMembershipPage(postbox: postbox, network: network, accountPeerId: accountPeerId, location: location, upperBound: next, collected: peers)
        }
    }
}
