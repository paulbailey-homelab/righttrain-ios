import SwiftUI

struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // App header
                AppHeader(surface: .neutral)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.top, RTSpacing.statusBarSafeArea)
                    .padding(.bottom, RTSpacing.compact)

                Spacer(minLength: RTSpacing.sectionGap)

                RightTrainLogoTile(size: 76)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.bottom, RTSpacing.compact)

                StatusPill(text: "Live journey guidance", tone: .green)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.bottom, RTSpacing.compact)

                Text("Plan once. Act when it changes.")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.rightTrainInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.bottom, RTSpacing.compact)

                Text("Set up a route or commute, and RightTrain watches its timing, platform, and disruptions. You're only alerted when you need to act.")
                    .font(.subheadline)
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.bottom, RTSpacing.sectionGap)

                privacyCallout
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.bottom, RTSpacing.sectionGap)

                // Simulator notice (only shows when App Attest unavailable)
                if !authViewModel.isDeviceAttestationSupported {
                    Text("RightTrain needs a real iPhone or iPad to set up this device. App Attest is not available on the simulator.")
                        .font(.footnote)
                        .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.bottom, RTSpacing.compact)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .readableContentMargins()
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: RTSpacing.small) {
                FloatingPrimaryAction {
                    Task { await authViewModel.registerDevice() }
                } label: {
                    HStack {
                        Text("Continue with this device")
                        Image(systemName: "arrow.right")
                    }
                }
                .disabled(!authViewModel.isDeviceAttestationSupported)
                .accessibilityLabel("Continue with this device")
                .accessibilityHint("Sets this device up anonymously with a private key. No email or password is needed.")

                Text("By continuing you agree to the privacy notice. You can clear this device from Settings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
            }
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
    }

    private var privacyCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.rightTrainInk)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("No contact details by default")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.rightTrainInk)
                Text("Your device gets a private key for journeys, commutes, and live alerts. No email, phone number, or password is needed.")
                    .font(.caption)
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rtCard(padding: RTSpacing.cardPadding)
        .accessibilityElement(children: .combine)
    }
}
