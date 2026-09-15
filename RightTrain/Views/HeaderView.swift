import SwiftUI

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
                // Darker tracks than the icon's: faint grey vanishes at
                // wordmark size.
                RightTrainRouteMark(trackColor: .rightTrainInk.opacity(RTOpacity.tertiary))
                    .frame(width: 22, height: 22)
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
