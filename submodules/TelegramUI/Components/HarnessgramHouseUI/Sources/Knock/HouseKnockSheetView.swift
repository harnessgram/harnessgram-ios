import Foundation
import UIKit
import SwiftUI
import HarnessgramCockpitKit
import HarnessgramHouseCore
import HarnessgramHouseKit

/// What one sheet shows. A knock comes from a Cockpit decision (it can be answered) or, when the Cockpit does not list
/// the question, only from the bridge's message (the sheet then offers to open the room).
public struct HouseKnockItem: Equatable, Identifiable {
    public enum Source: Equatable {
        case decision(HarnessgramCockpitSnapshot.Decision)
        case message(key: String)
    }

    public var source: Source
    public var question: String
    /// The room's name (the project group).
    public var roomTitle: String
    /// The line after the room's name in the Cockpit's topic ("מסך כניסה"), when there is one.
    public var detail: String?
    /// A Telegram link that opens the room's topic or the bot's chat (`tg://...`).
    public var openRoomLink: String?
    /// The agent's name, once the bridge sends it with the message; nil until then.
    public var agentName: String?
    /// New questions beyond this one that wait in the list.
    public var moreWaiting: Int

    public var id: String {
        switch self.source {
        case let .decision(decision):
            return "d:" + decision.id
        case let .message(key):
            return "m:" + key
        }
    }

    public var decision: HarnessgramCockpitSnapshot.Decision? {
        if case let .decision(decision) = self.source {
            return decision
        }
        return nil
    }

    public init(source: Source, question: String, roomTitle: String, detail: String? = nil, openRoomLink: String?, agentName: String? = nil, moreWaiting: Int = 0) {
        self.source = source
        self.question = question
        self.roomTitle = roomTitle
        self.detail = detail
        self.openRoomLink = openRoomLink
        self.agentName = agentName
        self.moreWaiting = moreWaiting
    }

    /// A Cockpit decision as a knock.
    public init(decision: HarnessgramCockpitSnapshot.Decision, moreWaiting: Int) {
        self.init(
            source: .decision(decision),
            question: decision.title,
            roomTitle: HouseKnockText.roomName(fromTopic: decision.topic),
            detail: HouseKnockText.topicDetail(fromTopic: decision.topic),
            openRoomLink: HarnessgramCockpitLinks.appURL(forTopicURL: decision.topicURL)?.absoluteString,
            moreWaiting: moreWaiting
        )
    }
}

/// The sheet's buttons call these; the controller wires them to the animation and to the knock center.
final class HouseKnockSheetModel: ObservableObject {
    let item: HouseKnockItem
    let plan: HouseWaitingRowPlan?
    let artKey: HouseRoomArtKey
    @Published var bottomInset: CGFloat = 0.0
    @Published var feedback: String?
    @Published var isBusy = false

    var onApprove: () -> Void = {}
    var onLater: () -> Void = {}
    var onOpenRoom: () -> Void = {}
    var onOpenWaitingList: (() -> Void)?

    init(item: HouseKnockItem, plan: HouseWaitingRowPlan?) {
        self.item = item
        self.plan = plan
        self.artKey = HouseRoomArtKey.key(forTitle: item.roomTitle)
    }
}

/// The knocker: a brass ring on a small plate, drawn in code (the art catalog has none yet; no plus or cross shapes).
struct HouseKnockerGlyph: View {
    var body: some View {
        let palette = HouseColors.light
        return ZStack {
            RoundedRectangle(cornerRadius: 5.0, style: .continuous)
                .fill(palette.brass.color)
                .frame(width: 20.0, height: 14.0)
                .offset(y: -20.0)
            Circle()
                .stroke(palette.brass.color, lineWidth: 5.0)
                .frame(width: 36.0, height: 36.0)
                .offset(y: 8.0)
            Circle()
                .stroke(palette.amberGlow.color.opacity(0.55), lineWidth: 1.0)
                .frame(width: 30.0, height: 30.0)
                .offset(y: 8.0)
        }
        .frame(width: 48.0, height: 60.0)
        .accessibilityHidden(true)
    }
}

/// The knock sheet (screens s07): an arched cedar top with the knocker, who is knocking, the room chip, the question on a
/// parchment card, then Approve (olive; the Face ID glyph when the decision is sensitive), "אחר כך" and "לפתוח את החדר".
/// It has no Telegram equivalent, so it is SwiftUI in a Display controller (`HouseKnockSheetController`), with the
/// House tokens only.
struct HouseKnockSheetView: View {
    @ObservedObject var model: HouseKnockSheetModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = self.colorScheme == .dark
        let palette = HouseTokens.colors(darkAppearance: dark)
        let onCedar = HouseColors.light.surface.color
        return VStack(spacing: HouseTokens.Space.md) {
            HouseKnockerGlyph()
                .padding(.top, HouseTokens.Radius.knockArchRise)
            self.header(onCedar: onCedar, palette: palette)
            self.questionCard(palette: palette)
            if let more = HouseKnockText.moreWaiting(self.model.item.moreWaiting) {
                self.moreLine(more, onCedar: onCedar)
            }
            if self.showsOpenRoomLink {
                Button(action: self.model.onOpenRoom) {
                    Text(HouseKnockStrings.t(.openRoom))
                        .underline()
                        .houseFont(.callout)
                        .foregroundColor(onCedar)
                        .frame(maxWidth: .infinity, minHeight: HouseTokens.Space.minTapTarget)
                }
                .accessibilityHint(Text(HouseKnockStrings.t(.waitingRowHint)))
            }
        }
        .padding(.horizontal, HouseTokens.Space.lg)
        .padding(.bottom, HouseTokens.Space.sm + self.model.bottomInset)
        .frame(maxWidth: .infinity)
        .background(
            ArchShape(rise: HouseTokens.Radius.knockArchRise)
                .fill(palette.cedar.color)
                .overlay(ArchShape(rise: HouseTokens.Radius.knockArchRise).stroke(palette.cedarDeep.color, lineWidth: 2.0))
                .ignoresSafeArea(edges: .bottom)
        )
        .environment(\.layoutDirection, .rightToLeft)
        .accessibilityAction(.escape, self.model.onLater)
    }

    /// The open-room link is a separate line only when the primary button is not already "open the room".
    private var showsOpenRoomLink: Bool {
        return self.model.item.openRoomLink != nil && self.model.plan != nil && self.model.plan?.style != .chooseInRoom
    }

    private func header(onCedar: Color, palette: HousePalette) -> some View {
        let image = HouseArtStore.shared.image(for: self.model.artKey, variant: .card)
        return HStack(alignment: .center, spacing: HouseTokens.Space.md) {
            ZStack {
                Circle().fill(palette.surfaceRaised.color)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                }
                Circle().stroke(palette.brass.color, lineWidth: 2.0)
            }
            .frame(width: 56.0, height: 56.0)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HouseTokens.Space.xs) {
                Text(HouseKnockStrings.title(agentName: self.model.item.agentName))
                    .houseFont(.title1)
                    .foregroundColor(onCedar)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(self.model.item.roomTitle)
                    .houseFont(.callout)
                    .foregroundColor(HouseColors.light.ink.color)
                    .padding(.horizontal, HouseTokens.Space.md)
                    .padding(.vertical, HouseTokens.Space.xs)
                    .background(Capsule().fill(HouseColors.light.surface.color))
                    .lineLimit(2)
            }
            Spacer(minLength: 0.0)
        }
    }

    private func questionCard(palette: HousePalette) -> some View {
        VStack(spacing: HouseTokens.Space.sm) {
            Text(self.model.item.question)
                .houseFont(.title3)
                .foregroundColor(palette.ink.color)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = self.model.item.detail {
                Text(detail)
                    .houseFont(.body)
                    .foregroundColor(palette.ink2.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let feedback = self.model.feedback {
                Text(feedback)
                    .houseFont(.callout)
                    .foregroundColor(palette.statusError.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            self.primaryButton
            Button(action: self.model.onLater) {
                Text(HouseKnockStrings.t(.later))
            }
            .buttonStyle(HouseButtonStyle(.outline))
        }
        .padding(HouseTokens.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: HouseTokens.Radius.card, style: .continuous)
                .fill(palette.surfaceRaised.color)
        )
    }

    @ViewBuilder
    private var primaryButton: some View {
        if let plan = self.model.plan, plan.style != .chooseInRoom {
            let sensitive = plan.style == .approveWithFaceID
            Button(action: self.model.onApprove) {
                HStack(spacing: HouseTokens.Space.sm) {
                    Text(HouseKnockStrings.t(.approve))
                    if sensitive {
                        Image(systemName: "faceid")
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(HouseButtonStyle(.olive))
            .disabled(self.model.isBusy)
            .accessibilityLabel(Text(sensitive ? HouseKnockStrings.t(.approveFaceIDHint) : HouseKnockStrings.t(.approve)))
        } else {
            // A choice question, or a message the Cockpit does not list: the room is where it is answered.
            Button(action: self.model.onOpenRoom) {
                Text(self.model.plan?.style == .chooseInRoom ? HouseKnockStrings.t(.choose) : HouseKnockStrings.t(.openRoom))
            }
            .buttonStyle(HouseButtonStyle(.olive))
            .disabled(self.model.item.openRoomLink == nil)
        }
    }

    private func moreLine(_ text: String, onCedar: Color) -> some View {
        Group {
            if let open = self.model.onOpenWaitingList {
                Button(action: open) {
                    Text(text)
                        .underline()
                        .houseFont(.callout)
                        .foregroundColor(onCedar)
                        .frame(maxWidth: .infinity, minHeight: HouseTokens.Space.minTapTarget)
                }
            } else {
                Text(text)
                    .houseFont(.callout)
                    .foregroundColor(onCedar)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
