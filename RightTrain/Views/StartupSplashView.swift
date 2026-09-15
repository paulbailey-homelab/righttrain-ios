import SwiftUI

/// The RightTrain route mark (diverging grey tracks, green through-line),
/// drawn with the same geometry as the app icon (see
/// scripts/generate-righttrain-icons.swift) so the splash matches the brand
/// instead of a placeholder SF Symbol. Colours are parameterised for the
/// cream in-app context.
struct RightTrainRouteMark: View {
    var trackColor: Color = .rightTrainInk.opacity(RTOpacity.faint)
    var routeColor: Color = .rightTrainSuccess

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 1024

            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s, y: y * s)
            }

            var upper = Path()
            upper.move(to: p(132, 270))
            upper.addLine(to: p(246, 270))
            upper.addCurve(to: p(386, 386), control1: p(314, 270), control2: p(322, 386))
            upper.addLine(to: p(728, 386))

            var lower = Path()
            lower.move(to: p(132, 756))
            lower.addLine(to: p(246, 756))
            lower.addCurve(to: p(386, 638), control1: p(314, 756), control2: p(322, 638))
            lower.addLine(to: p(728, 638))

            let trackStyle = StrokeStyle(lineWidth: 48 * s, lineCap: .round, lineJoin: .round)
            context.stroke(upper, with: .color(trackColor), style: trackStyle)
            context.stroke(lower, with: .color(trackColor), style: trackStyle)

            var route = Path()
            route.move(to: p(190, 512))
            route.addLine(to: p(878, 512))

            var arrowHead = Path()
            arrowHead.move(to: p(842, 450))
            arrowHead.addLine(to: p(916, 512))
            arrowHead.addLine(to: p(842, 574))

            let routeStyle = StrokeStyle(lineWidth: 50 * s, lineCap: .round, lineJoin: .round)
            context.stroke(route, with: .color(routeColor), style: routeStyle)
            context.stroke(arrowHead, with: .color(routeColor), style: routeStyle)

            let dot = Path(ellipseIn: CGRect(x: 138 * s, y: 446 * s, width: 132 * s, height: 132 * s))
            context.fill(dot, with: .color(routeColor))
        }
        .accessibilityHidden(true)
    }
}

/// The route mark on a rounded tile, as on the app icon: the one logo for
/// launch and sign-in.
struct RightTrainLogoTile: View {
    var size: CGFloat = 82

    var body: some View {
        RightTrainRouteMark()
            .frame(width: size * 0.78, height: size * 0.78)
            .frame(width: size, height: size)
            // A solid tile: the mark is content, and nothing floats above it
            // for glass to separate it from.
            .background(Color.rightTrainPaperCream, in: .rect(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct StartupSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.rightTrainSurfaceCream
                .ignoresSafeArea()

            VStack(spacing: RTSpacing.sectionGap) {
                RightTrainLogoTile()
                    .scaleEffect(isPulsing ? 1.04 : 1)

                VStack(spacing: RTSpacing.small) {
                    RightTrainBrand()
                        .foregroundStyle(Color.rightTrainInk)

                    Text("Starting RightTrain")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rightTrainInk.opacity(RTOpacity.dim))
                }

                ProgressView()
                    .tint(Color.rightTrainSuccess)
                    .controlSize(.regular)
                    .accessibilityLabel("Loading")
            }
            .padding(.horizontal, RTSpacing.pageHorizontal)
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
