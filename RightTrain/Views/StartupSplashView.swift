import SwiftUI

struct StartupSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.rightTrainSurfaceCream
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.rightTrainAccent)
                    .frame(width: 82, height: 82)
                    .background(
                        Color.rightTrainAccent.opacity(colorScheme == .dark ? 0.18 : 0.12),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.rightTrainInkFaint, lineWidth: 1)
                    }
                    .scaleEffect(isPulsing ? 1.04 : 1)

                VStack(spacing: 7) {
                    RightTrainBrand()

                    Text("Starting RightTrain")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .tint(Color.rightTrainAccent)
                    .controlSize(.regular)
                    .accessibilityLabel("Loading")
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RightTrain is starting")
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
