import SwiftUI

private enum SettingsConfirmation {
    case signOut
    case deleteAccount

    var title: String {
        switch self {
        case .signOut:
            return "Sign out of RightTrain?"
        case .deleteAccount:
            return "Permanently delete your RightTrain account?"
        }
    }

    var message: String {
        switch self {
        case .signOut:
            return "Your journeys and pins are saved to your account. You can sign back in on this device."
        case .deleteAccount:
            return "This permanently deletes your account and all saved journeys. It cannot be undone."
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
                profileSection(user)
                entitlementSection(user)
                planSection(user)
            }

            notificationSection
            liveActivitySection
            feedbackSection

            aboutSection

            accountSection
        }
        .safeAreaPadding(.bottom, RTSpacing.bottomSafeArea)
        .scrollContentBackground(.hidden)
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
        .lightSurfaceForeground()
        .toolbarColorScheme(.light, for: .navigationBar)
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
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private func profileSection(_ user: User) -> some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: RTSize.profileIcon))
                    .foregroundStyle(Color.rightTrainActionInk)

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayNameOrFallback)
                        .font(.headline)
                    Text(user.maskedEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if let email = user.email, !email.isEmpty {
                SettingsValueRow(
                    title: "Email Status",
                    systemImage: user.emailVerified ? "checkmark.seal" : "exclamationmark.triangle",
                    value: user.emailVerified ? "Verified" : "Unverified"
                )
                SettingsValueRow(
                    title: "Email Type",
                    systemImage: user.isPrivateEmail ? "envelope.badge" : "envelope",
                    value: user.isPrivateEmail ? "Private relay" : "Direct email"
                )
            } else {
                SettingsValueRow(
                    title: "Account",
                    systemImage: "iphone",
                    value: "Device-only"
                )
            }
        } header: {
            settingsSectionHeader("Profile", systemImage: "person.crop.circle")
        }
        .listRowBackground(Color.rightTrainPaperCream)
    }

    @ViewBuilder
    private func entitlementSection(_ user: User) -> some View {
        Section {
            entitlementCard(user)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        } header: {
            settingsSectionHeader("Your Plan", systemImage: "speedometer")
        }
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
                    .foregroundStyle(Color.rightTrainActionInk.opacity(0.72))

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
             Text(" / \(pinsLimit) pins used").foregroundStyle(Color.rightTrainInk.opacity(0.82)))
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
                .foregroundStyle(Color.rightTrainInk.opacity(0.58))
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
            if let paid = user.entitlements.paidSubscription {
                SettingsValueRow(title: "Plan", systemImage: "crown", value: "Pro")
                SettingsValueRow(
                    title: "Renewal",
                    systemImage: paid.willRenew ? "arrow.triangle.2.circlepath" : "calendar.badge.exclamationmark",
                    value: paid.willRenew ? "Renews automatically" : "Ends after current period"
                )
                if let expiresAt = paid.expiresAt {
                    SettingsValueRow(
                        title: "Valid Until",
                        systemImage: "calendar",
                        value: expiresAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            } else {
                SettingsValueRow(title: "Plan", systemImage: "testtube.2", value: "Free Beta")
            }

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
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }

            if user.entitlements.paidSubscription != nil {
                Button {
                    Task { await subscriptionViewModel.openManageSubscriptions() }
                } label: {
                    Label("Manage Subscription", systemImage: "gearshape")
                }
            }
        } header: {
            settingsSectionHeader("Plan", systemImage: "creditcard")
        } footer: {
            Text("Pro unlocks up to 10 Search Pins and 10 saved commutes.")
        }
        .listRowBackground(Color.rightTrainPaperCream)
    }

    private var notificationSection: some View {
        Section {
            NotificationPermissionView()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.rightTrainPaperCream)
        } header: {
            settingsSectionHeader("Notifications", systemImage: "bell")
        } footer: {
            Text("RightTrain only needs alerts for action-needed changes: platform moves, cancellations, delays, interchange risk, and better options.")
        }
    }

    private var liveActivitySection: some View {
        Section {
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
            settingsSectionHeader("Live Activity", systemImage: "rectangle.on.rectangle")
        } footer: {
            Text("See the same route, status, platform, and next-action language used on the Lock Screen and Dynamic Island.")
        }
        .listRowBackground(Color.rightTrainPaperCream)
        .sensoryFeedback(.success, trigger: liveActivityPreviewFeedbackTrigger)
    }

    private var feedbackSection: some View {
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
        } header: {
            settingsSectionHeader("Feedback", systemImage: "bubble.left.and.bubble.right")
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

    private var accountSection: some View {
        Group {
            Section {
                if let portableAccount = authViewModel.portableAccount {
                    SettingsValueRow(
                        title: "Account Mode",
                        systemImage: "key",
                        value: portableAccount.account.mode.capitalized
                    )
                    SettingsValueRow(
                        title: "Preference Version",
                        systemImage: "number",
                        value: "\(portableAccount.lastSyncedPreferenceVersion)"
                    )
                    if let lastSyncedAt = portableAccount.lastSyncedAt {
                        SettingsValueRow(
                            title: "Last Synced",
                            systemImage: "clock",
                            value: lastSyncedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if let preferenceSet = authViewModel.accountPreferenceSet {
                        SettingsValueRow(
                            title: "Synced Categories",
                            systemImage: "checklist",
                            value: preferenceCategorySummary(preferenceSet)
                        )
                    }
                    NavigationLink {
                        LinkedDevicesView()
                    } label: {
                        Label("Linked Devices", systemImage: "iphone.gen3")
                    }
                    NavigationLink {
                        AccountPrivacyControlsView()
                    } label: {
                        Label("Privacy Controls", systemImage: "hand.raised")
                    }
                } else {
                    NavigationLink {
                        AccountCreationView()
                    } label: {
                        Label("Create Account", systemImage: "key.badge.plus")
                    }
                    NavigationLink {
                        AccountRestoreView()
                    } label: {
                        Label("Restore Account", systemImage: "arrow.down.circle")
                    }
                }

                if let message = authViewModel.accountStatusMessage {
                    Label(message, systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(Color.rightTrainActionInk)
                }
            } header: {
                settingsSectionHeader("Portable Account", systemImage: "person.crop.circle.badge.checkmark")
            } footer: {
                Text("Account creation is optional. Device-only use stays available, and portable accounts sync preferences without email or phone number lookup.")
            }
            .listRowBackground(Color.rightTrainPaperCream)

            Section {
                Button(role: .destructive) {
                    confirmation = .signOut
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } header: {
                settingsSectionHeader("Account", systemImage: "person.crop.circle.badge.minus")
            } footer: {
                Text("Signs you out on this device.")
            }
            .listRowBackground(Color.rightTrainPaperCream)

            Section {
                if authViewModel.hasPortableAccount {
                    NavigationLink {
                        AccountPrivacyControlsView()
                    } label: {
                        Label("Export or Delete Account", systemImage: "hand.raised")
                    }
                }

                Button(role: .destructive) {
                    confirmation = .deleteAccount
                } label: {
                    Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                }
                .foregroundStyle(Color.rightTrainDanger)
            } footer: {
                Text("Permanently removes active profile, journey, and account preference data. Limited audit records may be retained where required.")
                    .foregroundStyle(Color.rightTrainDanger)
            }
            .listRowBackground(Color.rightTrainPaperCream)
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
        case .signOut:
            Button("Sign Out", role: .destructive) {
                Task { await authViewModel.signOut() }
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

    private func preferenceCategorySummary(_ preferenceSet: AccountPreferenceSet) -> String {
        var categories = ["stations"]
        if !preferenceSet.commuteRoutines.isEmpty {
            categories.append("routines")
        }
        if preferenceSet.notificationPreferences.routineNotificationsEnabled != nil {
            categories.append("notifications")
        }
        if !preferenceSet.productPreferences.isEmpty {
            categories.append("products")
        }
        return categories.joined(separator: ", ")
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
