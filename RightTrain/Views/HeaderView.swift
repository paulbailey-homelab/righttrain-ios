import SwiftUI

// MARK: - Signal mark

/// The RightTrain brand mark: a square housing with a single round signal light.
/// Renders using `currentColor` (foregroundStyle), so it inherits the surface ink.
struct SignalMark: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width
            let strokeW = s * (1.6 / 22)
            let r = s * (4.5 / 22)
            let inset = strokeW / 2

            // Square housing
            let rect = Path(
                roundedRect: CGRect(
                    x: inset + s * (1.5 / 22),
                    y: inset + s * (1.5 / 22),
                    width: s - 2 * (inset + s * (1.5 / 22)),
                    height: s - 2 * (inset + s * (1.5 / 22))
                ),
                cornerRadius: r
            )
            ctx.stroke(rect, with: .foreground, lineWidth: strokeW)

            // Central signal circle (filled)
            let circleR = s * (5.0 / 22)
            let circlePath = Path(ellipseIn: CGRect(
                x: s / 2 - circleR,
                y: s / 2 - circleR,
                width: circleR * 2,
                height: circleR * 2
            ))
            ctx.fill(circlePath, with: .foreground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - App header

/// Compact brand header for non-live surfaces. Active journey route, status,
/// timing, and next-action hierarchy is owned by the live glance components so
/// navigation chrome does not displace first-screen guidance.
struct AppHeader: View {
    /// Surface context — controls text colour.
    var surface: RTSurface = .neutral

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // Brand
            HStack(alignment: .center, spacing: 5) {
                SignalMark(size: 18)
                Text("RightTrain")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(surface.ink)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Monochrome brand mark (Components.swift `RightTrainBrand` replacement)
// The split "Right" / "Train" colour treatment is retired. All uses of
// RightTrainBrand now render a plain monochrome wordmark.

struct RightTrainBrand: View {
    enum Style {
        case largeTitle
        case title
    }

    var style: Style = .largeTitle

    var body: some View {
        Text("RightTrain")
            .font(font)
            .accessibilityLabel("RightTrain")
    }

    private var font: Font {
        switch style {
        case .largeTitle:
            return .system(.largeTitle, design: .default, weight: .bold)
        case .title:
            return .system(.title, design: .default, weight: .bold)
        }
    }
}

// MARK: - Legacy HeaderView (kept for any navigation-bar contexts)

struct HeaderView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        if authViewModel.isSignedIn {
            AppHeader(surface: .neutral)
        }
    }
}
