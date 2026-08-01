import SwiftUI

struct HomeView: View {
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let onStart: () -> Void

    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let scale = min(width / 1846, height / 852)

            ZStack {
                Image("home_hero_battle_aligned")
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.28),
                        Color.black.opacity(0.10),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: UnitPoint(x: 0.48, y: 0.5)
                )
                .allowsHitTesting(false)

                brandLockup(scale: scale)
                    .frame(width: 760 * scale, alignment: .leading)
                    .position(x: 515 * scale, y: 286 * scale)

                statsStrip(scale: scale)
                    .frame(width: 1040 * scale, height: 76 * scale)
                    .position(x: 630 * scale, y: 742 * scale)

                startButton(scale: scale)
                    .frame(width: 540 * scale, height: 108 * scale)
                    .position(x: 1470 * scale, y: 738 * scale)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.58, dampingFraction: 0.88)) {
                appeared = true
            }
        }
    }

    private func brandLockup(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            ZStack(alignment: .leading) {
                Text(L10n.text("app.title"))
                    .font(.system(size: 188 * scale, weight: .black, design: .rounded))
                    .tracking(-9 * scale)
                    .foregroundStyle(GameTheme.coral.opacity(0.55))
                    .offset(x: 3 * scale, y: 4 * scale)

                Text(L10n.text("app.title"))
                    .font(.system(size: 188 * scale, weight: .black, design: .rounded))
                    .tracking(-9 * scale)
                    .foregroundStyle(Color(red: 0.98, green: 0.96, blue: 0.89))
                    .shadow(color: .black.opacity(0.45), radius: 5 * scale, y: 5 * scale)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.52)
            .allowsTightening(true)

            HStack(spacing: 14 * scale) {
                speedLines(color: GameTheme.cyan, scale: scale)

                Text(L10n.text("app.secondary_name"))
                    .font(.system(size: 62 * scale, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(Color(red: 0.97, green: 0.95, blue: 0.88))
                    .shadow(color: .black.opacity(0.35), radius: 3 * scale, y: 3 * scale)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                speedLines(color: GameTheme.coral, scale: scale)
            }

            Text(L10n.text("home.tagline"))
                .font(.system(size: 30 * scale, weight: .semibold, design: .rounded))
                .tracking(2.1 * scale)
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.45), radius: 3 * scale, y: 2 * scale)
                .padding(.top, 18 * scale)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -24 * scale)
    }

    private func speedLines(color: Color, scale: CGFloat) -> some View {
        VStack(spacing: 5 * scale) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: (92 - CGFloat(index) * 13) * scale, height: 6 * scale)
            }
        }
    }

    private func statsStrip(scale: CGFloat) -> some View {
        HStack(spacing: 26 * scale) {
            statItem(
                icon: "crown.fill",
                label: L10n.text("stats.best_rank"),
                value: bestRankLetter,
                color: bestRankColor,
                scale: scale
            )

            Rectangle()
                .fill(.white.opacity(0.48))
                .frame(width: 1, height: 42 * scale)

            statItem(
                icon: "timer",
                label: L10n.text("stats.best_short"),
                value: formattedBestTime,
                color: GameTheme.cyan,
                scale: scale
            )

            Rectangle()
                .fill(.white.opacity(0.48))
                .frame(width: 1, height: 42 * scale)

            statItem(
                icon: "sparkles",
                label: L10n.text("stats.best_dodge"),
                value: bestDodgedCount == 0 ? "—" : "\(bestDodgedCount)",
                color: GameTheme.coral,
                scale: scale
            )
        }
        .padding(.horizontal, 28 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.72))
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 8 * scale, y: 4 * scale)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16 * scale)
    }

    private func statItem(
        icon: String,
        label: String,
        value: String,
        color: Color,
        scale: CGFloat
    ) -> some View {
        HStack(spacing: 16 * scale) {
            Image(systemName: icon)
                .font(.system(size: 31 * scale, weight: .bold))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 23 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 36 * scale, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func startButton(scale: CGFloat) -> some View {
        Button(action: onStart) {
            HStack(spacing: 18 * scale) {
                Text(L10n.text("home.start"))
                    .font(.system(size: 38 * scale, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 8 * scale)

                Image(systemName: "arrow.right")
                    .font(.system(size: 31 * scale, weight: .black))
            }
            .foregroundStyle(Color(red: 0.07, green: 0.055, blue: 0.04))
            .padding(.horizontal, 40 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.34),
                        Color(red: 0.94, green: 0.65, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.black.opacity(0.72), lineWidth: 3 * scale)
                    .padding(2 * scale)
            }
            .shadow(color: .black.opacity(0.28), radius: 8 * scale, y: 5 * scale)
        }
        .buttonStyle(HomePressButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18 * scale)
        .accessibilityHint(L10n.text("home.start_hint"))
    }

    private var formattedBestTime: String {
        guard bestSurvivalTime > 0 else { return "—" }
        return L10n.format("format.seconds_short", bestSurvivalTime)
    }

    private var bestRankLetter: String {
        guard bestSurvivalTime > 0 else { return "—" }
        switch bestSurvivalTime {
        case 45...: return "S"
        case 35...: return "A"
        case 20...: return "B"
        default: return "C"
        }
    }

    private var bestRankColor: Color {
        switch bestRankLetter {
        case "S": return GameTheme.gold
        case "A": return GameTheme.mint
        case "B": return GameTheme.cyan
        case "C": return GameTheme.coral
        default: return .white.opacity(0.72)
        }
    }
}

private struct HomePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

#Preview("Landscape Japanese") {
    HomeView(bestSurvivalTime: 41.7, bestDodgedCount: 93, onStart: {})
        .frame(width: 932, height: 430)
}
