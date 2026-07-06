import ActivityKit
import SwiftUI

private enum SettingsConfirmation {
    case logOutAccount
    case clearDevice
    case deleteAccount

    var title: String {
        switch self {
        case .logOutAccount:
            return "Log out of RightTrain?"
        case .clearDevice:
            return "Clear this device?"
        case .deleteAccount:
            return "Permanently delete your RightTrain account?"
        }
    }

    var message: String {
        switch self {
        case .logOutAccount:
            return "Your synced preferences stay in your account."
        case .clearDevice:
            return "This removes saved RightTrain data from this device."
        case .deleteAccount:
            return "This permanently deletes your account data. It cannot be undone."
        }
    }
}

struct SettingsProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @Environment(NotificationViewModel.self) private var notificationViewModel
    @Environment(SubscriptionViewModel.self) private var subscriptionViewModel
    @State private var confirmation: SettingsConfirmation?
    @State private var liveActivityPreviewFeedbackTrigger = 0

    private let privacyURL = URL(string: "https://righttrain.app/privacy")!
    private let termsURL = URL(string: "https://righttrain.app/terms")!
    private let supportURL = URL(string: "mailto:support@righttrain.app")!

    var body: some View {
        Form {
            if let user = authViewModel.user {
                accountSection
                planSection(user)
            } else {
                accountSection
            }

            alertsSection
            supportSection
            aboutSection
            dangerZoneSection
        }
        .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea)
        .scrollContentBackground(.hidden)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .lightSurfaceForeground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationViewModel.refreshStatus()
            if authViewModel.isSignedIn {
                await subscriptionViewModel.refresh()
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: confirmationPresented, titleVisibility: .visible) {
            confirmationButtons
        } message: {
            Text(confirmation?.message ?? "")
        }
    }

    private var accountSection: some View {
        Section {
            accountStatusRow

            if authViewModel.hasPortableAccount {
                NavigationLink {
                    LinkedDevicesView()
                } label: {
                    Label("Manage devices", systemImage: "iphone.gen3")
                }

                NavigationLink {
                    AccountPrivacyControlsView()
                } label: {
                    Label("Export data", systemImage: "square.and.arrow.down")
                }
            } else {
                NavigationLink {
                    AccountCreationView()
                } label: {
                    Label("Create account", systemImage: "key.badge.plus")
                }

                NavigationLink {
                    AccountRestoreView()
                } label: {
                    Label("Log in", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
        } header: {
            settingsSectionHeader("Account", systemImage: "person.crop.circle")
        } footer: {
            Text(authViewModel.hasPortableAccount ? "Manage the devices and data linked to your account." : "Create or log in to an account to sync preferences on another device.")
        }
        .listRowBackground(Color.rightTrainPaperCream)
    }

    private var accountStatusRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: authViewModel.hasPortableAccount ? "person.crop.circle.fill" : "iphone")
                .font(.system(size: RTSize.profileIcon))
                .foregroundStyle(Color.rightTrainActionInk)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(authViewModel.hasPortableAccount ? "Account" : "This device")
                    .font(.headline)
                Text(authViewModel.hasPortableAccount ? "Logged in with passkey" : "No account")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Entitlement usage card using the same neutral surface as the rest of Settings.
    private func entitlementCard(_ user: User) -> some View {
        let pinsUsed  = activeWindowCount
        let pinsLimit = user.entitlements.activeWindowLimit
        let isPro     = user.entitlements.paidSubscription != nil
        let fraction  = pinsLimit > 0 ? Double(pinsUsed) / Double(pinsLimit) : 0

        return VStack(alignment: .leading, spacing: RTSpacing.compact) {
            // Eyebrow + renewal date
            HStack(alignment: .firstTextBaseline) {
                Text(isPro ? "PRO · ACTIVE" : "FREE BETA")
                    .font(RTFont.eyebrow)
                    .tracking(2)
                    .foregroundStyle(Color.rightTrainActionInk.opacity(RTOpacity.emphasized))

                Spacer()

                if let paid = user.entitlements.paidSubscription,
                   let expiresAt = paid.expiresAt {
                    Text("Renews \(expiresAt.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.rightTrainInk.opacity(0.52))
                }
            }

            (Text("\(pinsUsed)").foregroundStyle(Color.rightTrainActionInk) +
             Text(" of \(pinsLimit) pins used").foregroundStyle(Color.rightTrainInk.opacity(0.82)))
                .font(.system(size: 26, weight: .bold))

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.rightTrainInk.opacity(0.12))
                    Capsule()
                        .fill(Color.rightTrainActionInk)
                        .frame(width: max(6, geo.size.width * fraction))
                }
                .frame(height: 6)
            }
            .frame(height: 6)

            // Feature caption
            Text("Multi-leg journeys · connection risk alerts · window monitoring")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainActionInk.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, RTSpacing.small)
    }

    @ViewBuilder
    private func planSection(_ user: User) -> some View {
        Section {
            entitlementCard(user)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

            ForEach(subscriptionViewModel.products) { product in
                Button {
                    Task { await subscriptionViewModel.purchase(product) }
                } label: {
                    HStack {
                        Label(product.period.humanizedIdentifier, systemImage: product.period == "annual" ? "calendar" : "calendar.badge.clock")
                        Spacer()
                        Text(product.displayPrice)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task { await subscriptionViewModel.restore() }
            } label: {
                Label("Restore purchases", systemImage: "arrow.clockwise")
            }

            if user.entitlements.paidSubscription != nil {
                Button {
                    Task { await subscriptionViewModel.openManageSubscriptions() }
                } label: {
                    Label("Manage subscription", systemImage: "gearshape")
                }
            }
        } header: {
            settingsSectionHeader("Plan", systemImage: "creditcard")
        } footer: {
            Text("Pro unlocks up to 10 search pins and 10 saved commutes.")
        }
        .listRowBackground(Color.rightTrainPaperCream)
    }

    private var alertsSection: some View {
        Section {
            NotificationPermissionView()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.rightTrainPaperCream)

            if !ActivityAuthorizationInfo().areActivitiesEnabled {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    HStack {
                        Label("Live Activities are off", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Color.rightTrainDanger)
                        Spacer()
                        Text("Turn on in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Opens iOS Settings so you can allow Live Activities for RightTrain.")
            }

            Button {
                liveActivityPreviewFeedbackTrigger += 1
                Task { await activeWindowViewModel.previewLiveActivity() }
            } label: {
                HStack {
                    Label("Preview Live Activity", systemImage: "iphone")
                    Spacer()
                    Text("30 sec")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityHint("Starts a short local Live Activity preview.")
        } header: {
            settingsSectionHeader("Alerts", systemImage: "bell")
        } footer: {
            Text("Live Activity preview runs for 30 seconds.")
        }
        .listRowBackground(Color.rightTrainPaperCream)
        .sensoryFeedback(.success, trigger: liveActivityPreviewFeedbackTrigger)
    }

    private var supportSection: some View {
        Section {
            Link(destination: supportURL) {
                HStack {
                    Label("Report a journey issue", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    Spacer()
                    Text("Email")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: supportURL) {
                HStack {
                    Label("Send app feedback", systemImage: "envelope")
                    Spacer()
                    Text("Support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ShareLink(item: BetaDiagnostics.exportText()) {
                HStack {
                    Label("Share Diagnostics", systemImage: "waveform.path.ecg")
                    Spacer()
                    Text("Recent events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            settingsSectionHeader("Support", systemImage: "bubble.left.and.bubble.right")
        } footer: {
            Text("Include the route, train time, platform, and what RightTrain showed so support can compare it with the live feed.")
        }
        .listRowBackground(Color.rightTrainPaperCream)
    }

    private var aboutSection: some View {
        Section {
            SettingsValueRow(title: "App Version", systemImage: "info.circle", value: appVersionText)

            Link(destination: privacyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            Link(destination: termsURL) {
                Label("Terms", systemImage: "doc.text")
            }
        } header: {
            settingsSectionHeader("About", systemImage: "info.circle")
        }
        .listRowBackground(Color.rightTrainPaperCream)
    }

    private var dangerZoneSection: some View {
        Section {
            if authViewModel.hasPortableAccount {
                Button(role: .destructive) {
                    confirmation = .logOutAccount
                } label: {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Button(role: .destructive) {
                    confirmation = .deleteAccount
                } label: {
                    Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                }
            } else {
                Button(role: .destructive) {
                    confirmation = .clearDevice
                } label: {
                    Label("Clear This Device", systemImage: "iphone.slash")
                }
            }
        } header: {
            settingsSectionHeader("Danger Zone", systemImage: "exclamationmark.triangle")
        } footer: {
            Text(authViewModel.hasPortableAccount ? "Log out of this device or permanently delete the account." : "Clears saved RightTrain data from this device.")
                .foregroundStyle(Color.rightTrainDanger)
        }
        .listRowBackground(Color.rightTrainPaperCream)
        .foregroundStyle(Color.rightTrainDanger)
    }

    private var activeWindowCount: Int {
        activeWindowViewModel.activeWindow?.entitlement.activeWindowCount ?? 0
    }

    private var confirmationTitle: String {
        confirmation?.title ?? ""
    }

    private var confirmationPresented: Binding<Bool> {
        Binding {
            confirmation != nil
        } set: { isPresented in
            if !isPresented {
                confirmation = nil
            }
        }
    }

    @ViewBuilder
    private var confirmationButtons: some View {
        switch confirmation {
        case .logOutAccount:
            Button("Log Out", role: .destructive) {
                Task { await authViewModel.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        case .clearDevice:
            Button("Clear This Device", role: .destructive) {
                Task { await authViewModel.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        case .deleteAccount:
            Button("Delete Account", role: .destructive) {
                Task { await authViewModel.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        case nil:
            EmptyView()
        }
    }

    private var appVersionText: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return build
        default:
            return "Unavailable"
        }
    }

    private func settingsSectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
    }

}

private struct SettingsValueRow: View {
    var title: String
    var systemImage: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.primary, Color.rightTrainActionInk)

            Spacer(minLength: 12)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
