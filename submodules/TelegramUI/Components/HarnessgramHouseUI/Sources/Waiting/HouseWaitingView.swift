import Foundation
import UIKit
import SwiftUI
import HarnessgramCockpitKit
import HarnessgramHouseCore
import HarnessgramHouseKit

/// The waiting list (screens s08): every open decision across the rooms, newest first, each with its room's picture and
/// its own actions. The rows follow `HouseWaitingRowPlan`: a plain yes/no question is answered right in the row, a sensitive
/// one has one "אישור" button with the Face ID glyph that opens the app flow (Face ID first), and a question with
/// several answers has "לבחור", which opens the room. It sits under Telegram's own navigation bar (title and back button
/// are Telegram's); only the rows are the House's, since Telegram has no list row with inline answers.
struct HouseWaitingView: View {
    @ObservedObject var model: HouseWaitingModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let palette = HouseTokens.colors(darkAppearance: self.colorScheme == .dark)
        let gutter = self.horizontalSizeClass == .regular ? HouseTokens.Space.gutterTablet : HouseTokens.Space.gutterPhone
        return ScrollView {
            VStack(spacing: HouseTokens.Space.cardGap) {
                self.header(palette: palette)
                if self.model.decisions.isEmpty {
                    self.emptyState(palette: palette)
                } else {
                    ForEach(self.model.decisions) { decision in
                        HouseWaitingRow(model: self.model, decision: decision)
                    }
                    self.footer(palette: palette)
                }
            }
            .padding(.horizontal, gutter)
            .padding(.top, HouseTokens.Space.sm)
            .padding(.bottom, HouseTokens.Space.sectionGap)
            .frame(maxWidth: 640.0)
            .frame(maxWidth: .infinity)
        }
        .background(palette.bg.color.ignoresSafeArea())
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            self.model.start()
        }
        .onDisappear {
            self.model.stop()
        }
    }

    private func header(palette: HousePalette) -> some View {
        let count = self.model.decisions.count
        return VStack(spacing: HouseTokens.Space.sm) {
            if count > 0 {
                LanternBadge(count: count)
            }
            Text(count > 0 ? HouseKnockText.thingsCount(count) : HouseKnockStrings.t(.waitingEmptyTitle))
                .houseFont(.title1)
                .foregroundColor(palette.ink.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, HouseTokens.Space.xxl)
        .padding(.bottom, HouseTokens.Space.lg)
        .padding(.horizontal, HouseTokens.Space.lg)
        .frame(maxWidth: .infinity)
        .background(
            ArchShape(rise: 56.0)
                .fill(palette.surface.color)
                .overlay(ArchShape(rise: 56.0).stroke(palette.border.color, lineWidth: 1.0))
        )
    }

    private func emptyState(palette: HousePalette) -> some View {
        VStack(spacing: HouseTokens.Space.md) {
            if let image = UIImage(named: "House/Empty/empty-waiting", in: .main, compatibleWith: nil) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300.0)
                    .accessibilityHidden(true)
            }
            Text(HouseKnockStrings.t(.waitingEmptyBody))
                .houseFont(.body)
                .foregroundColor(palette.ink2.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, HouseTokens.Space.xxl)
        .frame(maxWidth: .infinity)
    }

    private func footer(palette: HousePalette) -> some View {
        Text(HouseKnockStrings.t(.waitingFooter))
            .houseFont(.callout)
            .foregroundColor(palette.ink3.color)
            .multilineTextAlignment(.center)
            .padding(.top, HouseTokens.Space.sm)
            .frame(maxWidth: .infinity)
    }
}

/// One decision: the room's name with its window, the question, the buttons, and the room's picture on the starting side.
struct HouseWaitingRow: View {
    @ObservedObject var model: HouseWaitingModel
    let decision: HarnessgramCockpitSnapshot.Decision
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let palette = HouseTokens.colors(darkAppearance: self.colorScheme == .dark)
        let artKey = HouseRoomArtKey.key(forTitle: self.decision.topic)
        return HouseCard {
            // At accessibility text sizes the picture sits above the text instead of beside it.
            if self.dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: HouseTokens.Space.md) {
                    self.art(key: artKey, palette: palette)
                    self.textColumn(palette: palette)
                }
            } else {
                HStack(alignment: .top, spacing: HouseTokens.Space.md) {
                    self.art(key: artKey, palette: palette)
                    self.textColumn(palette: palette)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text(HouseKnockStrings.t(.openRoom))) {
            self.model.openRoom(self.decision)
        }
    }

    private func textColumn(palette: HousePalette) -> some View {
        let roomName = HouseKnockText.roomName(fromTopic: self.decision.topic)
        let detail = HouseKnockText.topicDetail(fromTopic: self.decision.topic)
        return VStack(alignment: .leading, spacing: HouseTokens.Space.sm) {
            HStack(spacing: HouseTokens.Space.sm) {
                Text(roomName)
                    .houseFont(.title2)
                    .foregroundColor(palette.ink.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                WindowStatusView(state: .waiting, accessibilityText: HouseKnockStrings.t(.waitingWindow))
                    .frame(width: 12.0, height: 16.0)
            }
            Text(self.decision.title)
                .houseFont(.body)
                .foregroundColor(palette.ink.color)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .houseFont(.callout)
                    .foregroundColor(palette.ink2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            self.buttons(palette: palette)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func art(key: HouseRoomArtKey, palette: HousePalette) -> some View {
        let image = HouseArtStore.shared.image(for: key, variant: .card)
        return Button(action: {
            self.model.openRoom(self.decision)
        }) {
            ZStack {
                ArchShape(rise: 48.0).fill(palette.border.color)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(ArchShape(rise: 48.0))
                }
                ArchShape(rise: 48.0).stroke(palette.borderStrong.color, lineWidth: 1.0)
            }
            .frame(width: 96.0, height: 96.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!self.model.canOpenRoom(self.decision))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func buttons(palette: HousePalette) -> some View {
        let plan = self.model.plan(for: self.decision)
        let state = self.model.rowStates[self.decision.id]
        VStack(alignment: .leading, spacing: HouseTokens.Space.sm) {
            HStack(spacing: HouseTokens.Space.sm) {
                switch plan.style {
                case .answerInPlace, .answerViaApp:
                    Button(plan.yesLabel) {
                        self.model.answer(self.decision, .yes)
                    }
                    .buttonStyle(HouseButtonStyle(.olive))
                    Button(plan.noLabel) {
                        self.model.answer(self.decision, .no)
                    }
                    .buttonStyle(HouseButtonStyle(.outline))
                case .approveWithFaceID:
                    Button(action: {
                        self.model.approveWithFaceID(self.decision)
                    }) {
                        HStack(spacing: HouseTokens.Space.sm) {
                            Text(HouseKnockStrings.t(.approve))
                            Image(systemName: "faceid")
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(HouseButtonStyle(.olive))
                    .accessibilityLabel(Text(HouseKnockStrings.t(.approveFaceIDHint)))
                    if self.model.canOpenRoom(self.decision) {
                        Button(HouseKnockStrings.t(.seeFirst)) {
                            self.model.openRoom(self.decision)
                        }
                        .buttonStyle(HouseButtonStyle(.outline))
                    }
                case .chooseInRoom:
                    Button(HouseKnockStrings.t(.choose)) {
                        self.model.openRoom(self.decision)
                    }
                    .buttonStyle(HouseButtonStyle(.outline))
                    .disabled(!self.model.canOpenRoom(self.decision))
                }
            }
            .disabled(state == .sending)
            if state == .sending {
                Text(HouseKnockStrings.t(.sending))
                    .houseFont(.callout)
                    .foregroundColor(palette.ink2.color)
            } else if case let .failed(text)? = state {
                Text(text)
                    .houseFont(.callout)
                    .foregroundColor(palette.statusError.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
