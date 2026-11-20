import StoreKit
import SwiftUI
import UIKit

/// Sheet from the Properties toolbar. Everything here is either a link out or a StoreKit call.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPro) private var isPro
    @Environment(\.openURL) private var openURL

    @State private var showsPaywall = false

    private static let privacyPolicyURL = URL(string: "https://apps-site-six.vercel.app/apps/turnproof/privacy")!
    private static let supportURL = URL(string: "https://apps-site-six.vercel.app/apps/turnproof/support")!
    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            Form {
                Section("Turnproof Pro") {
                    LabeledContent("Plan") {
                        Text(isPro ? "Pro" : "Free")
                    }
                    Button("See Plans") { showsPaywall = true }
                    Button("Restore Purchases") {
                        Task { try? await AppStore.sync() }
                    }
                }

                Section("Privacy") {
                    Button {
                        openSystemSettings()
                    } label: {
                        HStack {
                            Text("Camera Access")
                                .foregroundStyle(TPColor.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Link("Privacy Policy", destination: Self.privacyPolicyURL)
                }

                Section {
                    Link("Contact Support", destination: Self.supportURL)
                    Link("Terms of Use", destination: Self.termsURL)
                } header: {
                    Text("Help")
                } footer: {
                    Text(versionText).sectionFooterStyle()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("settings.done")
                }
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallScreen()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Turnproof \(version) (\(build))"
    }
}
