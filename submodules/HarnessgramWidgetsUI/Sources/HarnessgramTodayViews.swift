import Foundation
import SwiftUI
import UIKit
import WidgetKit
import HarnessgramCockpitKit

struct HarnessgramTodayViewModel {
    struct Row {
        let title: String
        let age: String
        let url: URL
    }

    let strings: HarnessgramWidgetStrings.Today
    let progress: String
    let fractionDone: Double
    let rows: [Row]
    let emptyText: String
    /// No Cockpit login for this account: the widget asks to connect (and a tap opens the pairing link) instead of
    /// claiming there is nothing to do today.
    let needsPairing: Bool
    let isSample: Bool

    init(today: HarnessgramCockpitSnapshot.Today, strings: HarnessgramWidgetStrings.Today, bridgeOrigin: URL? = nil, needsPairing: Bool = false, isSample: Bool = false) {
        self.strings = strings
        self.needsPairing = needsPairing
        self.isSample = isSample
        self.progress = strings.progress(done: today.doneToday, total: today.totalToday)
        self.fractionDone = today.totalToday > 0 ? Double(today.doneToday) / Double(today.totalToday) : 0
        // Recheck cached snapshots from versions that accepted any HTTPS host.
        self.rows = today.waiting.prefix(HarnessgramCockpitSnapshot.Today.maxWaiting).compactMap { row in
            guard let url = isSample ? HarnessgramSampleStore.openURL : HarnessgramCockpitLinks.todayURL(row.url.absoluteString, bridgeOrigin: bridgeOrigin) else {
                return nil
            }
            return Row(title: row.title, age: strings.age(minutes: row.ageMinutes), url: url)
        }
        if needsPairing {
            self.emptyText = HarnessgramWidgetStrings.needsPairing
        } else {
            self.emptyText = today == .empty ? strings.empty : strings.nothingWaiting
        }
    }
}

@available(iOS 17.0, *)
struct HarnessgramTodayContent: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let model: HarnessgramTodayViewModel
    let family: WidgetFamily

    private var compact: Bool {
        return self.family == .accessoryRectangular
    }

    private var usesRowLinks: Bool {
        return self.family == .systemMedium
    }

    var visibleRows: ArraySlice<HarnessgramTodayViewModel.Row> {
        return self.compact ? self.model.rows.prefix(2) : self.model.rows[...]
    }

    var tapURL: URL {
        if self.model.isSample {
            return HarnessgramSampleStore.openURL
        }
        if self.model.needsPairing {
            return HarnessgramCockpitLinks.pairURL
        }
        if self.usesRowLinks {
            return HarnessgramCockpitLinks.openURL
        }
        return self.visibleRows.first?.url ?? HarnessgramCockpitLinks.cockpitURL
    }

    private var accent: Color {
        return self.renderingMode == .fullColor ? HarnessgramWidgetPalette.accent : .primary
    }

    private var secondary: Color {
        return self.renderingMode == .fullColor ? .secondary : .primary
    }

    var body: some View {
        let rows = self.visibleRows
        VStack(alignment: .leading, spacing: self.compact ? 2 : 5) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .foregroundStyle(self.accent)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(self.model.isSample ? HarnessgramWidgetStrings.sampleData : self.compact ? self.model.progress : self.model.strings.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(self.compact ? .system(size: 13, weight: .semibold) : .footnote.weight(.semibold))

            if !self.compact {
                Text(self.model.progress)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ProgressView(value: self.model.fractionDone)
                    .tint(self.accent)
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }

            if rows.isEmpty {
                Text(self.model.emptyText)
                    .font(self.compact ? .system(size: 11) : .caption)
                    .foregroundStyle(self.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                ForEach(rows.indices, id: \.self) { index in
                    self.waitingRow(rows[index])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.primary)
        .environment(\.layoutDirection, self.model.strings.isRightToLeft ? .rightToLeft : .leftToRight)
        .widgetURL(self.tapURL)
        .containerBackground(for: .widget) {
            if !self.compact {
                LinearGradient(
                    colors: [Color(.systemBackground), HarnessgramWidgetPalette.accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color.clear
            }
        }
    }

    private func waitingRow(_ row: HarnessgramTodayViewModel.Row) -> some View {
        let label = HStack(spacing: self.compact ? 4 : 6) {
            Image(systemName: "clock")
                .foregroundStyle(self.accent)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text(row.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.age)
                .monospacedDigit()
                .foregroundStyle(self.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(self.compact ? .system(size: 11, weight: .medium) : .caption.weight(.medium))
        .foregroundStyle(Color.primary)
        .contentShape(Rectangle())

        return Group {
            if self.usesRowLinks {
                Link(destination: row.url) { label }
            } else {
                label
            }
        }
        .privacySensitive()
    }
}
