import Foundation
import UIKit
import SwiftUI
import Display
import AccountContext
import TelegramAudio
import HarnessgramSettings
import HarnessgramCockpitSync

struct HarnessgramRadioView: View {
    @ObservedObject var radio: HarnessgramRadioPlayer
    let audioSession: ManagedAudioSession
    @State private var linkText: String = ""
    @State private var hasLink: Bool = HarnessgramRadioLink.load() != nil
    @State private var linkMessage: String?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)
                    Text(HarnessgramStrings.t(.radioStation))
                        .font(.title2)
                    Text(self.radio.stateText)
                        .foregroundColor(.secondary)
                    Button(action: {
                        self.radio.toggle(audioSession: self.audioSession)
                    }) {
                        Label(self.radio.buttonTitle, systemImage: self.radio.state == .playing ? "pause.fill" : (self.radio.state == .connecting ? "xmark" : "play.fill"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.harnessgramFilled)
                    .disabled(!self.hasLink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section(header: Text(HarnessgramStrings.t(.radioLinkSection)), footer: Text(HarnessgramStrings.t(.radioLinkFooter))) {
                if self.hasLink {
                    Text(HarnessgramStrings.t(.radioLinkSaved))
                    Button(role: .destructive, action: {
                        self.radio.stop()
                        HarnessgramRadioLink.clear()
                        self.hasLink = false
                        self.linkMessage = nil
                    }) {
                        Text(HarnessgramStrings.t(.radioLinkForget))
                    }
                } else {
                    TextField(HarnessgramStrings.t(.radioLinkPlaceholder), text: self.$linkText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .environment(\.layoutDirection, self.linkText.isEmpty ? .rightToLeft : .leftToRight)
                    Button(action: {
                        let value = self.linkText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if HarnessgramRadioLink.streamURL(fromListenLink: value) != nil, HarnessgramRadioLink.save(value, pairedOrigin: HarnessgramCockpitSync.shared.viewState?.bridgeOrigin) {
                            self.linkText = ""
                            self.hasLink = true
                            self.linkMessage = nil
                        } else {
                            if let host = HarnessgramRadioLink.host(ofListenLink: value), !HarnessgramRadioLink.isAllowedHost(host, trustedHost: HarnessgramRadioLink.trustedHost(), pairedOrigin: HarnessgramCockpitSync.shared.viewState?.bridgeOrigin) {
                                self.linkMessage = HarnessgramRadioLink.missingHostMessage
                            } else {
                                self.linkMessage = HarnessgramStrings.t(.radioLinkInvalid)
                            }
                        }
                    }) {
                        Text(HarnessgramStrings.t(.radioLinkSave))
                    }
                    .disabled(self.linkText.isEmpty)
                    Text(self.linkMessage ?? HarnessgramStrings.t(.radioLinkMissing))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

public func harnessgramRadioController(context: AccountContext) -> ViewController {
    if HarnessgramSettings.shared.houseFeature(.radioScreen) {
        return HarnessgramRadioHouseScreen(context: context)
    }
    let view = HarnessgramRadioView(radio: .shared, audioSession: context.sharedContext.mediaManager.audioSession)
    return HarnessgramHostingScreen(context: context, title: HarnessgramStrings.t(.radioTitle), content: view)
}
