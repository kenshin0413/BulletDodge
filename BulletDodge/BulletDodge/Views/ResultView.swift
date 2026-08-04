import SwiftUI

struct ResultView: View {
    let result: GameResult
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let didSetTimeRecord: Bool
    let didSetDodgedRecord: Bool
    let onRetry: () -> Void
    let onHome: () -> Void

    @State private var appeared = false

    private var rank: ResultRank {
        ResultRank(survivalTime: result.survivalTime)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let scale = min(width / 1846, height / 852)

            ZStack {
                resultBackground(width: width, height: height)

                identityColumn(scale: scale)
                    .frame(width: 520 * scale, height: 742 * scale)
                    .position(x: 410 * scale, y: 422 * scale)

                performanceColumn(scale: scale)
                    .frame(width: 780 * scale, height: 730 * scale)
                    .position(x: 1195 * scale, y: 414 * scale)
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.64, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private func resultBackground(width: CGFloat, height: CGFloat) -> some View {
        Image("result_ledger_opaque_bg")
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func identityColumn(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(L10n.text("result.training_complete"))
                .font(.system(size: 82 * scale, weight: .black, design: .rounded))
                .tracking(-3 * scale)
                .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.075))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .padding(.top, 38 * scale)

            ornamentedLabel(L10n.text("stats.rank"), scale: scale)
                .padding(.top, 36 * scale)

            Text(rank.letter)
                .font(.system(
                    size: (rank.letter == "SS" ? 250 : 348) * scale,
                    weight: .black,
                    design: .serif
                ))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.84, blue: 0.43),
                            Color(red: 0.72, green: 0.43, blue: 0.11),
                            Color(red: 0.94, green: 0.68, blue: 0.23)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 0.30, green: 0.19, blue: 0.07), radius: 1 * scale)
                .shadow(color: .black.opacity(0.30), radius: 5 * scale, y: 7 * scale)
                .lineLimit(1)
                .frame(height: 312 * scale)
                .scaleEffect(appeared ? 1 : 0.80)
                .opacity(appeared ? 1 : 0)

            Text(rank.message)
                .font(.system(size: 21 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.09))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 500 * scale)
                .padding(.top, 12 * scale)

            ornamentLine(scale: scale)
                .frame(width: 330 * scale)
                .padding(.top, 24 * scale)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -18 * scale)
        .accessibilityElement(children: .contain)
    }

    private func ornamentedLabel(_ text: String, scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            ornamentLine(scale: scale)
            Text(text)
                .font(.system(size: 28 * scale, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.57, green: 0.38, blue: 0.14))
                .lineLimit(1)
            ornamentLine(scale: scale)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("accessibility.rank", rank.letter))
    }

    private func ornamentLine(scale: CGFloat) -> some View {
        HStack(spacing: 5 * scale) {
            Rectangle()
                .fill(Color(red: 0.64, green: 0.45, blue: 0.20).opacity(0.78))
                .frame(height: max(1, 1.5 * scale))
            Image(systemName: "diamond.fill")
                .font(.system(size: 9 * scale, weight: .bold))
                .foregroundStyle(Color(red: 0.73, green: 0.50, blue: 0.18))
            Rectangle()
                .fill(Color(red: 0.64, green: 0.45, blue: 0.20).opacity(0.78))
                .frame(height: max(1, 1.5 * scale))
        }
        .frame(maxWidth: .infinity)
    }

    private func performanceColumn(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(L10n.text("result.survival_time"))
                .font(.system(size: 24 * scale, weight: .black, design: .rounded))
                .tracking(3.2 * scale)
                .foregroundStyle(Color(red: 0.12, green: 0.25, blue: 0.25))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 9 * scale) {
                Text(L10n.format("format.decimal_one", result.survivalTime))
                    .font(.system(size: 160 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .tracking(-5 * scale)
                    .foregroundStyle(Color(red: 0.02, green: 0.61, blue: 0.70))
                    .shadow(color: .white.opacity(0.85), radius: 1 * scale, y: 1 * scale)
                    .shadow(color: Color(red: 0.02, green: 0.22, blue: 0.25).opacity(0.20), radius: 2 * scale, y: 2 * scale)

                Text(L10n.text("result.seconds"))
                    .font(.system(size: 32 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.02, green: 0.42, blue: 0.48))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -14 * scale)

            completionRule(scale: scale)
                .padding(.top, 2 * scale)

            VStack(spacing: 0) {
                resultRow(
                    label: L10n.text("stats.dodged"),
                    value: "\(result.dodgedCount)",
                    accent: Color(red: 0.04, green: 0.22, blue: 0.25),
                    badge: nil,
                    scale: scale
                )

                resultRow(
                    label: L10n.text("stats.avoidance_rate"),
                    value: "\(avoidanceRate)%",
                    accent: Color(red: 0.04, green: 0.22, blue: 0.25),
                    badge: nil,
                    scale: scale
                )

                resultRow(
                    label: L10n.text("stats.movement_speed"),
                    value: L10n.text(
                        "settings.speed.\(result.playerSpeedSetting.rawValue)"
                    ),
                    accent: Color(red: 0.04, green: 0.22, blue: 0.25),
                    badge: nil,
                    scale: scale
                )

                resultRow(
                    label: L10n.text("stats.best_short"),
                    value: formattedBestTime,
                    accent: Color(red: 0.04, green: 0.22, blue: 0.25),
                    badge: didSetTimeRecord ? L10n.text("stats.new") : nil,
                    scale: scale
                )

                resultRow(
                    label: L10n.text("stats.best_dodge"),
                    value: "\(bestDodgedCount)",
                    accent: Color(red: 0.04, green: 0.22, blue: 0.25),
                    badge: didSetDodgedRecord ? L10n.text("stats.new") : nil,
                    scale: scale
                )
            }
            .padding(.top, 5 * scale)

            Spacer(minLength: 18 * scale)

            actionRow(scale: scale)
                .frame(height: 98 * scale)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 18 * scale)
    }

    private func completionRule(scale: CGFloat) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(GameTheme.cyan.opacity(0.90))
                .frame(width: 74 * scale, height: max(1, 2 * scale))

            Rectangle()
                .fill(GameTheme.cyan.opacity(0.90))
                .frame(maxWidth: .infinity)
                .frame(height: max(1, 2 * scale))

            Circle()
                .fill(GameTheme.cyan)
                .frame(width: 10 * scale, height: 10 * scale)
                .shadow(color: GameTheme.cyan.opacity(0.55), radius: 5 * scale)
        }
    }

    private func resultRow(
        label: String,
        value: String,
        accent: Color,
        badge: String?,
        scale: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 13 * scale) {
                Text(label)
                    .font(.system(size: 27 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.08))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 12 * scale)

                if let badge {
                    Text(badge)
                        .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.10, blue: 0.03))
                        .padding(.horizontal, 9 * scale)
                        .padding(.vertical, 5 * scale)
                        .background(GameTheme.gold, in: RoundedRectangle(cornerRadius: 6 * scale))
                }

                Text(value)
                    .font(.system(size: 45 * scale, weight: .medium, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            .frame(height: 68 * scale)

            HStack(spacing: 8 * scale) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 7 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 0.69, green: 0.48, blue: 0.20))
                Rectangle()
                    .fill(Color(red: 0.61, green: 0.44, blue: 0.23).opacity(0.70))
                    .frame(height: max(1, 1.25 * scale))
                Image(systemName: "diamond.fill")
                    .font(.system(size: 7 * scale, weight: .bold))
                    .foregroundStyle(Color(red: 0.69, green: 0.48, blue: 0.20))
            }
        }
    }

    private func actionRow(scale: CGFloat) -> some View {
        HStack(spacing: 26 * scale) {
            Button(action: onRetry) {
                HStack(spacing: 15 * scale) {
                    Text(L10n.text("result.retry"))
                        .font(.system(size: 31 * scale, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)

                    Spacer(minLength: 4 * scale)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 27 * scale, weight: .black))
                }
                .foregroundStyle(Color(red: 0.11, green: 0.075, blue: 0.025))
                .padding(.horizontal, 38 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.83, blue: 0.35),
                            Color(red: 0.86, green: 0.59, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(Color(red: 0.25, green: 0.16, blue: 0.05), lineWidth: 3 * scale)
                        .padding(2 * scale)
                }
                .shadow(color: .black.opacity(0.24), radius: 8 * scale, y: 6 * scale)
            }
            .buttonStyle(ResultPressButtonStyle())

            Button(action: onHome) {
                HStack(spacing: 10 * scale) {
                    Image(systemName: "house.fill")
                    Text(L10n.text("result.home"))
                        .lineLimit(1)
                }
                .font(.system(size: 24 * scale, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.94, green: 0.90, blue: 0.79))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.09, green: 0.085, blue: 0.075).opacity(0.94), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color(red: 0.53, green: 0.35, blue: 0.12), lineWidth: 2 * scale)
                }
            }
            .buttonStyle(ResultPressButtonStyle())
            .frame(width: 240 * scale)
        }
    }

    private var avoidanceRate: Int {
        let total = result.dodgedCount + result.hitCount
        guard total > 0 else { return 0 }
        return Int((Double(result.dodgedCount) / Double(total) * 100).rounded())
    }

    private var formattedBestTime: String {
        guard bestSurvivalTime > 0 else { return "—" }
        return L10n.format("format.seconds_short", bestSurvivalTime)
    }
}

private struct ResultPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

private struct ResultRank {
    let letter: String
    let headline: String
    let message: String
    let color: Color

    init(survivalTime: TimeInterval) {
        if survivalTime >= 68 {
            letter = "SS"
            headline = L10n.text("rank.ss.headline")
            message = L10n.text("rank.ss.message")
            color = GameTheme.violet
        } else if survivalTime >= 45 {
            letter = "S"
            headline = L10n.text("rank.s.headline")
            message = L10n.text("rank.s.message")
            color = GameTheme.gold
        } else if survivalTime >= 35 {
            letter = "A"
            headline = L10n.text("rank.a.headline")
            message = L10n.text("rank.a.message")
            color = GameTheme.mint
        } else if survivalTime >= 20 {
            letter = "B"
            headline = L10n.text("rank.b.headline")
            message = L10n.text("rank.b.message")
            color = GameTheme.cyan
        } else if survivalTime >= 10 {
            letter = "C"
            headline = L10n.text("rank.c.headline")
            message = L10n.text("rank.c.message")
            color = GameTheme.coral
        } else {
            letter = "D"
            headline = L10n.text("rank.d.headline")
            message = L10n.text("rank.d.message")
            color = GameTheme.softText
        }
    }
}

#Preview("Landscape") {
    ResultView(
        result: GameResult(
            survivalTime: 31.4,
            dodgedCount: 62,
            hitCount: 3,
            playerSpeedSetting: .normal
        ),
        bestSurvivalTime: 104.8,
        bestDodgedCount: 369,
        didSetTimeRecord: false,
        didSetDodgedRecord: false,
        onRetry: {},
        onHome: {}
    )
    .frame(width: 932, height: 430)
}
