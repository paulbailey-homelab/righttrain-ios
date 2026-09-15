import SwiftUI

/// The RightTrain route mark (a route chosen between two diverging tracks),
/// drawn with the same geometry as the app icon: keep in step with `Mark` in
/// scripts/generate-righttrain-icons.swift. On the neutral in-app tile the
/// route is brand green and the tracks faint ink, where the icon puts a white
/// route on green.
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
            upper.move(to: p(138, 280))
            upper.addLine(to: p(238, 280))
            upper.addCurve(to: p(378, 392), control1: p(306, 280), control2: p(314, 392))
            upper.addLine(to: p(708, 392))

            var lower = Path()
            lower.move(to: p(138, 744))
            lower.addLine(to: p(238, 744))
            lower.addCurve(to: p(378, 632), control1: p(306, 744), control2: p(314, 632))
            lower.addLine(to: p(708, 632))

            let style = StrokeStyle(lineWidth: 64 * s, lineCap: .round, lineJoin: .round)
            context.stroke(upper, with: .color(trackColor), style: style)
            context.stroke(lower, with: .color(trackColor), style: style)

            var route = Path()
            route.move(to: p(188, 512))
            route.addLine(to: p(858, 512))

            var arrowHead = Path()
            arrowHead.move(to: p(814, 440))
            arrowHead.addLine(to: p(888, 512))
            arrowHead.addLine(to: p(814, 584))

            context.stroke(route, with: .color(routeColor), style: style)
            context.stroke(arrowHead, with: .color(routeColor), style: style)

            let dot = Path(ellipseIn: CGRect(x: 128 * s, y: 440 * s, width: 144 * s, height: 144 * s))
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
