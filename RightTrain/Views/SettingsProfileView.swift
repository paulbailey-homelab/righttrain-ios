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
            return "Delete your RightTrain account?"
        }
    }

    var message: String {
        switch self {
        case .logOutAccount:
            return "Your commutes stay in your iCloud, and come back when you log in again."
        case .clearDevice:
            return "This removes saved RightTrain data from this device."
        case .deleteAccount:
            return "Everything RightTrain holds about you is deleted, and this can't be undone. Your commutes are in your own iCloud, so they stay until you remove them in Settings › Apple Account › iCloud."
        }
    }
}

struct SettingsProfileView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(CommuteRoutinesViewModel.self) private var commuteRoutinesViewModel
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

            commuteStorageSection
            alertsSection
            supportSection
            aboutSection
            dangerZoneSection
        }
        .readableContentMargins()
        .tint(Color.rightTrainActionInk)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await notificationViewModel.refreshStatus()
            await commuteRoutinesViewModel.refreshCloudKitAvailability()
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
            Text("Account")
        } footer: {
            Text(authViewModel.hasPortableAccount ? "Manage the devices and data linked to your account." : "Create or log in to an account to keep your pins and alerts when you change device.")
        }
    }

    private var accountStatusRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: authViewModel.hasPortableAccount ? "person.crop.circle.fill" : "iphone")
                .font(.system(size: RTSize.profileIcon))
                .symbolRenderingMode(.hierarchical)
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

    /// Plan status and pin usage, laid out as an ordinary grouped-list row.
    private func entitlementRow(_ user: User) -> some View {
        let pinsUsed  = activeWindowCount
        let pinsLimit = user.entitlements.activeWindowLimit
        let isPro     = user.entitlements.paidSubscription != nil
        let fraction  = pinsLimit > 0 ? min(1, Double(pinsUsed) / Double(pinsLimit)) : 0

        return VStack(alignment: .leading, spacing: RTSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(isPro ? "RightTrain Pro" : "Free beta")
                    .font(.headline)

                Spacer()

                if let paid = user.entitlements.paidSubscription,
                   let expiresAt = paid.expiresAt {
                    Text("Renews \(expiresAt.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: fraction) {
                Text("\(pinsUsed) of \(pinsLimit) pins used")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .tint(Color.rightTrainActionInk)

            Text("Multi-leg journeys, connection risk alerts and window monitoring.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func planSection(_ user: User) -> some View {
        Section {
            entitlementRow(user)

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
            Text("Plan")
        } footer: {
            Text("Pro unlocks up to 10 search pins and 10 saved commutes.")
        }
    }

    private var alertsSection: some View {
        Section {
            NotificationPermissionView()
                .listRowInsets(EdgeInsets())
        
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
            Text("Alerts")
        } footer: {
            Text("Live Activity preview runs for 30 seconds.")
        }
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

            NavigationLink {
                ScrollView {
                    BetaOnboardingView(forceExpanded: true)
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.vertical, RTSpacing.pageVertical)
                }
                .readableContentMargins()
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Beta Guidance")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Beta guidance", systemImage: "testtube.2")
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
            Text("Support")
        } footer: {
            Text("Include the route, train time, platform, and what RightTrain showed so support can compare it with the live feed.")
        }
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
            Text("About")
        }
    }

    /// Where commutes actually live, and whether that place is reachable.
    ///
    /// The Commutes tab says this too, but only once something has broken.
    /// Settings is where someone comes to find out why, so the state belongs
    /// here whether it is working or not.
    private var commuteStorageSection: some View {
        Section {
            SettingsAccountValueRow(
                title: "Commutes",
                systemImage: iCloudStatusIcon,
                value: iCloudStatusValue
            )
        } header: {
            Label("Storage", systemImage: "icloud")
        } footer: {
            Text(iCloudStatusFooter)
        }
    }

    private var iCloudStatusIcon: String {
        switch commuteRoutinesViewModel.cloudKitAvailability {
        case .available, .unknown:
            return "icloud"
        case .noAccount, .restricted, .unavailable:
            return "exclamationmark.icloud"
        }
    }

    private var iCloudStatusValue: String {
        switch commuteRoutinesViewModel.cloudKitAvailability {
        case .available:
            return "In your iCloud"
        case .noAccount:
            return "iCloud is off"
        case .restricted:
            return "iCloud not permitted"
        case .unavailable:
            return "iCloud unreachable"
        case .unknown:
            return "Checking"
        }
    }

    private var iCloudStatusFooter: String {
        switch commuteRoutinesViewModel.cloudKitAvailability {
        case .available, .unknown:
            return "Your commutes and station defaults are kept in your own private iCloud database. RightTrain's servers never hold them, and only see the individual departures it is asked to watch."
        case .noAccount:
            return "Commutes need iCloud, because RightTrain keeps them in your iCloud account rather than on its own servers. Sign in under Settings › Apple Account, and switch iCloud on for RightTrain, to use them."
        case .restricted:
            return "iCloud is not permitted on this device, so commutes are unavailable. Everything else in RightTrain still works."
        case .unavailable:
            return "iCloud could not be reached just now. Your commutes are safe; they will appear again once the connection recovers."
        }
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
        } footer: {
            Text(authViewModel.hasPortableAccount ? "Log out of this device or permanently delete the account. Neither touches the copy of your commutes in your iCloud." : "Clears saved RightTrain data from this device.")
        }
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
