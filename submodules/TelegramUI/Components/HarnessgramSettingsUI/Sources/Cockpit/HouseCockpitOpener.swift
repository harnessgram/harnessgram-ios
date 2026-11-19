import Foundation
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import HarnessgramAgent

/// Opens the full Cockpit Mini App (build 23) the way the bridge bot's menu button does: the pinned bridge bot (the same
/// checks as the widget login: its known username, a bot, and the pinned id from its own panel), its menu web app,
/// opened through Telegram's own web-app flow with the menu as the source. When the bot has no menu web app, or it
/// cannot be reached, the bot's chat opens instead, where the menu button is.
enum HouseCockpitOpener {
    private enum Target {
        case webApp(peer: EnginePeer, buttonText: String, url: String)
        case chat
    }

    static func open(context: AccountContext, parentController: ViewController, completion: @escaping (Bool) -> Void) {
        let engine = context.engine
        let signal: Signal<Target, NoError> = engine.peers.resolvePeerByName(name: HarnessgramAgentChat.bridgeBotResolveName, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> take(1)
        |> mapToSignal { peer -> Signal<Target, NoError> in
            guard let peer, case let .user(user) = peer, user.botInfo != nil, HarnessgramAgentChat.isBridgeBot(username: user.addressName), HarnessgramBridgeIdentity.shared.mayLogIn(userId: peer.id.id._internalGetInt64Value()) else {
                return .single(.chat)
            }
            return engine.peers.fetchAndUpdateCachedPeerData(peerId: peer.id)
            |> take(1)
            |> mapToSignal { _ -> Signal<Target, NoError> in
                return engine.data.get(TelegramEngine.EngineData.Item.Peer.BotMenu(id: peer.id))
                |> map { menu -> Target in
                    if let menu, case let .webView(text, url) = menu {
                        return .webApp(peer: peer, buttonText: text, url: url)
                    }
                    return .chat
                }
            }
        }
        |> timeout(15.0, queue: Queue.mainQueue(), alternate: .single(.chat))
        |> deliverOnMainQueue

        var finished = false
        let _ = signal.start(next: { [weak parentController] target in
            guard !finished else {
                return
            }
            finished = true
            switch target {
            case let .webApp(peer, buttonText, url):
                guard let parentController else {
                    completion(false)
                    return
                }
                context.sharedContext.openWebApp(context: context, parentController: parentController, updatedPresentationData: nil, botPeer: peer, chatPeer: peer, threadId: nil, buttonText: buttonText, url: url, simple: false, source: .menu, skipTermsOfService: false, payload: nil, verifyAgeCompletion: nil)
                completion(true)
            case .chat:
                HouseDecisionActions(context: context).open(url: "tg://resolve?domain=" + HarnessgramAgentChat.bridgeBotResolveName)
                completion(false)
            }
        }, completed: {
            if !finished {
                finished = true
                HouseDecisionActions(context: context).open(url: "tg://resolve?domain=" + HarnessgramAgentChat.bridgeBotResolveName)
                completion(false)
            }
        })
    }
}
