import Foundation
import UIKit
import SwiftUI
import HarnessgramSettings
import HarnessgramHouseCore

/// The one way a Harnessgram settings page draws a row (build 23, owner: "it is unclear what each thing does" and
/// "illustrate everything"). Every row has an icon in a tinted rounded square (Telegram's settings look), a title and
/// a one-line explanation; a segmented control always sits inside a labelled row; a row may carry a small live
/// preview under its control. The icon and the explanation are required parameters, and
/// HarnessgramSettingsRowsGuardTests (HarnessgramSettings) fails when a page draws a bare Toggle, Picker or Stepper.

/// The row's icon: an SF Symbol, white on a tinted rounded square.
struct HarnessgramRowIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: self.systemName)
            .font(.system(size: 15.0, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 29.0, height: 29.0)
            .background(RoundedRectangle(cornerRadius: 7.0, style: .continuous).fill(self.tint))
            .accessibilityHidden(true)
    }
}

/// The icon, the title and the explanation under it.
struct HarnessgramRowHeader: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 12.0) {
            HarnessgramRowIcon(systemName: self.icon, tint: self.tint)
            HarnessgramSettingsRowLabel(title: self.title, detail: self.detail)
        }
    }
}

/// A switch.
struct HarnessgramToggleRow<Preview: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let isOn: Binding<Bool>
    let preview: Preview

    init(icon: String, tint: Color, title: String, detail: String, isOn: Binding<Bool>, @ViewBuilder preview: () -> Preview) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        self.isOn = isOn
        self.preview = preview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Toggle(isOn: self.isOn) {
                HarnessgramRowHeader(icon: self.icon, tint: self.tint, title: self.title, detail: self.detail)
            }
            self.preview
        }
        .padding(.vertical, 2.0)
    }
}

extension HarnessgramToggleRow where Preview == EmptyView {
    init(icon: String, tint: Color, title: String, detail: String, isOn: Binding<Bool>) {
        self.init(icon: icon, tint: tint, title: title, detail: detail, isOn: isOn, preview: { EmptyView() })
    }
}

/// A row that opens another page, with its current value and the chevron (on the left in right-to-left pages).
struct HarnessgramLinkRow<Preview: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let value: String
    let action: () -> Void
    let preview: Preview

    init(icon: String, tint: Color, title: String, detail: String, value: String = "", action: @escaping () -> Void, @ViewBuilder preview: () -> Preview) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        self.value = value
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            Button(action: self.action) {
                HStack {
                    HarnessgramRowHeader(icon: self.icon, tint: self.tint, title: self.title, detail: self.detail)
                        .foregroundColor(.primary)
                    Spacer()
                    if !self.value.isEmpty {
                        Text(self.value)
                            .foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.forward")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
            self.preview
        }
        .padding(.vertical, 2.0)
    }
}

extension HarnessgramLinkRow where Preview == EmptyView {
    init(icon: String, tint: Color, title: String, detail: String, value: String = "", action: @escaping () -> Void) {
        self.init(icon: icon, tint: tint, title: title, detail: detail, value: value, action: action, preview: { EmptyView() })
    }
}

/// A segmented choice inside its labelled row ("רוחב הבועות: רגיל | רחב"), with its own explanation.
struct HarnessgramSegmentedRow<Value: Hashable, Preview: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let selection: Binding<Value>
    let options: [(Value, String)]
    let preview: Preview

    init(icon: String, tint: Color, title: String, detail: String, selection: Binding<Value>, options: [(Value, String)], @ViewBuilder preview: () -> Preview) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        self.selection = selection
        self.options = options
        self.preview = preview()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HarnessgramRowHeader(icon: self.icon, tint: self.tint, title: self.title, detail: self.detail)
            Picker(self.title, selection: self.selection) {
                ForEach(self.options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .accessibilityLabel(Text(self.title))
            self.preview
        }
        .padding(.vertical, 2.0)
    }
}

extension HarnessgramSegmentedRow where Preview == EmptyView {
    init(icon: String, tint: Color, title: String, detail: String, selection: Binding<Value>, options: [(Value, String)]) {
        self.init(icon: icon, tint: tint, title: title, detail: detail, selection: selection, options: options, preview: { EmptyView() })
    }
}

/// A choice from a list (a menu), inside its labelled row.
struct HarnessgramMenuRow<Value: Hashable>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let selection: Binding<Value>
    let options: [(Value, String)]

    var body: some View {
        HStack {
            HarnessgramRowHeader(icon: self.icon, tint: self.tint, title: self.title, detail: self.detail)
            Spacer()
            Picker(self.title, selection: self.selection) {
                ForEach(self.options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .accessibilityLabel(Text(self.title))
        }
        .padding(.vertical, 2.0)
    }
}

/// A number with minus and plus, inside its labelled row.
struct HarnessgramStepperRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let value: Binding<Int>
    let range: ClosedRange<Int>
    let valueText: String

    var body: some View {
        Stepper(value: self.value, in: self.range) {
            HStack {
                HarnessgramRowHeader(icon: self.icon, tint: self.tint, title: self.title, detail: self.detail)
                Spacer()
                Text(self.valueText)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2.0)
    }
}

/// A row with its own controls under the header (pairing, the bridge bot).
struct HarnessgramCustomRow<Content: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let content: Content

    init(icon: String, tint: Color, title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HarnessgramRowHeader(icon: self.icon, tint: self.tint, title: self.title, detail: self.detail)
            self.content
                .padding(.leading, 41.0)
        }
        .padding(.vertical, 2.0)
    }
}

/// Build 23 (PART G): under a control whose setting needs the app to be opened again (HarnessgramSettingApply.restart)
/// and changed since launch, a clear banner with "להפעיל מחדש עכשיו". It hides itself otherwise.
struct HarnessgramRestartBanner: View {
    let key: HarnessgramSettings.Key
    let text: String
    let restart: () -> Void
    var settings: HarnessgramSettings = .shared

    var body: some View {
        if self.settings.waitsForRestart(self.key) {
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(alignment: .top, spacing: 8.0) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(.orange)
                        .accessibilityHidden(true)
                    Text(self.text)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: self.restart) {
                    Text(HarnessgramRestartStrings.button)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36.0)
                }
                .buttonStyle(.harnessgramFilled(role: .warning))
            }
            .padding(10.0)
            .background(RoundedRectangle(cornerRadius: 10.0, style: .continuous).fill(Color.orange.opacity(0.12)))
        }
    }
}

/// Icon tints, one per family of settings (Telegram's settings use a few strong colours).
enum HarnessgramRowTint {
    static let look = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let text = Color(red: 0.20, green: 0.48, blue: 0.96)
    static let agents = Color(red: 0.19, green: 0.69, blue: 0.40)
    static let radio = Color(red: 0.97, green: 0.55, blue: 0.13)
    static let filter = Color(red: 0.90, green: 0.27, blue: 0.27)
    static let connect = Color(red: 0.10, green: 0.62, blue: 0.80)
    static let cockpit = Color(red: 0.13, green: 0.25, blue: 0.44)
    static let neutral = Color(red: 0.55, green: 0.57, blue: 0.62)
}

extension HouseColor {
    /// The colour for a SwiftUI preview.
    var swiftUIColor: Color {
        return Color(red: Double((self.rgb >> 16) & 0xff) / 255.0, green: Double((self.rgb >> 8) & 0xff) / 255.0, blue: Double(self.rgb & 0xff) / 255.0, opacity: self.alpha)
    }
}
