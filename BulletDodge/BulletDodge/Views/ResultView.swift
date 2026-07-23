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
        ResultRank(survivalTime: result.survivalTime, hitCount: result.hitCount)
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height * 1.25

            ZStack {
                ArenaShellBackground(glowColor: rank.color)

                ScrollView(showsIndicators: false) {
                    Group {
                        if isLandscape {
                            HStack(spacing: 22) {
                                summaryPanel
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                detailPanel
                                    .frame(width: min(470, geometry.size.width * 0.52))
                            }
                        } else {
                            VStack(spacing: 20) {
                                summaryPanel
                                    .frame(minHeight: 350)
                                detailPanel
                            }
                        }
                    }
                    .padding(.horizontal, isLandscape ? 28 : 20)
                    .padding(.vertical, isLandscape ? 20 : 28)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.66, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppMark()

            Spacer(minLength: 10)

            HStack(spacing: 22) {
                RankEmblem(rank: rank)
                    .frame(width: 142, height: 142)
                    .scaleEffect(appeared ? 1 : 0.74)

                VStack(alignment: .leading, spacing: 8) {
                    ModeTag(text: "Training complete", color: rank.color)

                    Text(rank.headline)
                        .font(.system(size: 33, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text(rank.message)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(GameTheme.softText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", result.survivalTime))
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("SECONDS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(rank.color)
            }
        }
        .padding(6)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -18)
    }

    private var detailPanel: some View {
        GameChromePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RUN SUMMARY")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white)
                        Text("今回のトレーニング結果")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(GameTheme.softText)
                    }

                    Spacer()

                    Text("回避率 \(avoidanceRate)%")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(GameTheme.mint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(GameTheme.mint.opacity(0.11), in: Capsule())
                }

                HStack(spacing: 9) {
                    ResultStat(icon: "sparkles", label: "DODGED", value: "\(result.dodgedCount)", color: GameTheme.cyan)
                    ResultStat(icon: "burst.fill", label: "HITS", value: "\(result.hitCount)", color: GameTheme.coral)
                    ResultStat(icon: "gauge.with.dots.needle.67percent", label: "RANK", value: rank.letter, color: rank.color)
                }

                HStack(spacing: 10) {
                    MetricTile(
                        icon: "trophy.fill",
                        title: "BEST TIME",
                        value: String(format: "%.1fs", bestSurvivalTime),
                        accent: GameTheme.gold,
                        badge: didSetTimeRecord ? "NEW" : nil
                    )
                    MetricTile(
                        icon: "star.fill",
                        title: "BEST DODGE",
                        value: "\(bestDodgedCount)",
                        accent: GameTheme.cyan,
                        badge: didSetDodgedRecord ? "NEW" : nil
                    )
                }

                HStack(spacing: 10) {
                    GamePrimaryButton(
                        title: "もう一度挑戦",
                        systemImage: "arrow.clockwise",
                        action: onRetry
                    )

                    GameSecondaryButton(
                        title: "ホーム",
                        systemImage: "house.fill",
                        action: onHome
                    )
                    .frame(maxWidth: 140)
                }
            }
            .padding(20)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 22)
    }

    private var avoidanceRate: Int {
        let total = result.dodgedCount + result.hitCount
        guard total > 0 else { return 0 }
        return Int((Double(result.dodgedCount) / Double(total) * 100).rounded())
    }
}

private struct ResultStat: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(GameTheme.softText)
            }

            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct RankEmblem: View {
    let rank: ResultRank

    var body: some View {
        ZStack {
            Circle()
                .fill(GameTheme.midnight.opacity(0.72))
                .overlay {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [rank.color.opacity(0.25), rank.color, .white.opacity(0.7), rank.color.opacity(0.25)],
                                center: .center
                            ),
                            lineWidth: 7
                        )
                }
                .shadow(color: rank.color.opacity(0.30), radius: 20)

            Circle()
                .stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                .padding(13)

            VStack(spacing: -4) {
                Text("RANK")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(GameTheme.softText)
                Text(rank.letter)
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ランク \(rank.letter)")
    }
}

private struct ResultRank {
    let letter: String
    let headline: String
    let message: String
    let color: Color

    init(survivalTime: TimeInterval, hitCount: Int) {
        if survivalTime >= 45, hitCount <= 2 {
            letter = "S"
            headline = "圧倒的な回避だ"
            message = "弾幕の流れを完全に読み切った。次は自己ベストを更新しよう。"
            color = GameTheme.gold
        } else if survivalTime >= 30 {
            letter = "A"
            headline = "鋭い反応だった"
            message = "危険な軌道をしっかり見切れている。Sランクはもう目前だ。"
            color = GameTheme.mint
        } else if survivalTime >= 15 {
            letter = "B"
            headline = "いい動きだ"
            message = "回避のリズムができてきた。次は視野を広く保ってみよう。"
            color = GameTheme.cyan
        } else {
            letter = "C"
            headline = "次はもっと行ける"
            message = "敵の予備動作を見れば軌道を先読みできる。もう一度挑戦しよう。"
            color = GameTheme.coral
        }
    }
}

#Preview("Landscape") {
    ResultView(
        result: GameResult(survivalTime: 31.4, dodgedCount: 62, hitCount: 3),
        bestSurvivalTime: 41.7,
        bestDodgedCount: 93,
        didSetTimeRecord: false,
        didSetDodgedRecord: true,
        onRetry: {},
        onHome: {}
    )
    .frame(width: 932, height: 430)
}
