import Postbox
import SwiftSignalKit
internal import TelegramApi

/// One server sweep of the installed sticker, mask and emoji packs on the filter's first run.
/// Archived and featured packs are not installed and are not grandfathered. Any failure leaves the
/// snapshot pending for the next startup; until then only bundled packs render.
func harnessgramCaptureInstalledStickerPacks(network: Network) -> Signal<Never, NoError> {
    guard HarnessgramPolicyStore.shared.needsStickerSnapshot() else {
        return .complete()
    }
    let requests: [Signal<Api.messages.AllStickers?, NoError>] = [
        network.request(Api.functions.messages.getAllStickers(hash: 0)),
        network.request(Api.functions.messages.getMaskStickers(hash: 0)),
        network.request(Api.functions.messages.getEmojiStickers(hash: 0))
    ].map { request in
        return request
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.messages.AllStickers?, NoError> in
            return .single(nil)
        }
    }
    return combineLatest(requests)
    |> take(1)
    |> map { results -> Void in
        var ids = Set<Int64>()
        var shortNames: [String] = []
        for result in results {
            // hash 0 always returns the full list; anything else is an incomplete snapshot.
            guard case let .allStickers(data)? = result else {
                return
            }
            for apiSet in data.sets {
                let info = StickerPackCollectionInfo(apiSet: apiSet, namespace: Namespaces.ItemCollection.CloudStickerPacks)
                ids.insert(info.id.id)
                shortNames.append(info.shortName)
            }
        }
        HarnessgramPolicyStore.shared.completeStickerSnapshot(HarnessgramPolicy.ApprovedStickerPacks(ids: ids, shortNames: shortNames))
    }
    |> ignoreValues
}
