import SwiftUI

struct SignInView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // App header
                    AppHeader(surface: .neutral)
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.top, RTSpacing.statusBarSafeArea)
                        .padding(.bottom, RTSpacing.compact)

                    Spacer(minLength: RTSpacing.sectionGap)

                    ZStack {
                        RoundedRectangle(cornerRadius: RTRadius.card)
                            .stroke(Color.rightTrainInk, lineWidth: 6)
                        Circle()
                            .fill(Color.rightTrainGoodBg)
                            .frame(width: 34, height: 34)
                    }
                    .frame(width: 76, height: 76)
                    .padding(.horizontal, RTSpacing.pageHorizontal)
                    .padding(.bottom, RTSpacing.compact)
                    .accessibilityHidden(true)

                    StatusPill(text: "Live journey guidance", tone: .green)
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.bottom, RTSpacing.compact)

                    Text("Plan once. Act when it changes.")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color.rightTrainInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, RTSpacing.pageHorizontal)
                        .padding(.bottom, RTSpacing.compact)

                    Text("Set up a route or routine, then let RightTrain watch the timing, platform, disruption, and next action. Alerts are for action-needed changes, not reassurance noise.")
                        .font(.system(size: 15, weight: .regular))
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

                    // Space for the bottom-anchored CTA
                    Spacer(minLength: 100)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            // Bottom-anchored CTA
            VStack(spacing: RTSpacing.compact) {
                Button {
                    Task { await authViewModel.registerDevice() }
                } label: {
                    HStack {
                        Text("Continue with this device")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.rtPrimary)
                .disabled(!authViewModel.isDeviceAttestationSupported)
                .opacity(authViewModel.isDeviceAttestationSupported ? 1 : 0.4)

                Text("By continuing you agree to the privacy notice. You can clear this device from Settings.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.rightTrainInk.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, RTSpacing.pageHorizontal)
            .padding(.bottom, 60)
            .padding(.top, RTSpacing.compact)
            .background(
                LinearGradient(
                    colors: [Color.rightTrainSurfaceCream.opacity(0), Color.rightTrainSurfaceCream],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.25)
                )
            )
        }
        .background(Color.rightTrainSurfaceCream.ignoresSafeArea())
    }

    private var privacyCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.rightTrainInk)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("No contact details by default")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.rightTrainInk)
                Text("Your device gets a private key for journeys, routines, and live alerts. No email, phone number, or password is needed.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, RTSpacing.cardPadding)
        .padding(.vertical, RTSpacing.compact)
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(Color.rightTrainInkFaint, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
