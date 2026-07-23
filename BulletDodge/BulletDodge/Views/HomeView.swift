import SwiftUI

struct HomeView: View {
    let bestSurvivalTime: TimeInterval
    let bestDodgedCount: Int
    let onStart: () -> Void

    @State private var appeared = false

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height * 1.25

            ZStack {
                ArenaShellBackground(glowColor: GameTheme.coral)

                ScrollView(showsIndicators: false) {
                    Group {
                        if isLandscape {
                            HStack(spacing: 24) {
                                heroPanel
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                missionPanel
                                    .frame(width: min(390, geometry.size.width * 0.43))
                            }
                        } else {
                            VStack(spacing: 20) {
                                heroPanel
                                    .frame(minHeight: 390)
                                missionPanel
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
            withAnimation(.spring(response: 0.62, dampingFraction: 0.86)) {
                appeared = true
            }
        }
    }

    private var heroPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppMark()

            Spacer(minLength: 12)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    ModeTag(text: "Arena online", color: GameTheme.mint)

                    Text("BULLET\nDODGE")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .tracking(-1.8)
                        .foregroundStyle(.white)
                        .lineSpacing(-5)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .allowsTightening(true)

                    Text("一瞬の判断で、すべてを避けろ。")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(GameTheme.softText)
                        .lineLimit(2)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                CharacterStage()
                    .frame(width: 165, height: 205)
                    .offset(y: 5)
            }
        }
        .padding(6)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
    }

    private var missionPanel: some View {
        GameChromePanel {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    ModeTag(text: "Survival training")
                    Spacer()
                    Text("SOLO")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(GameTheme.gold)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("弾幕を読み切れ")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("敵の投射を見極め、限界までアリーナに残ろう。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(GameTheme.softText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    MetricTile(
                        icon: "timer",
                        title: "BEST TIME",
                        value: formattedBestTime,
                        accent: GameTheme.cyan
                    )
                    MetricTile(
                        icon: "sparkles",
                        title: "BEST DODGE",
                        value: bestDodgedCount == 0 ? "—" : "\(bestDodgedCount)",
                        accent: GameTheme.coral
                    )
                }

                HStack(spacing: 8) {
                    TrainingRule(icon: "figure.run", text: "移動で回避")
                    TrainingRule(icon: "scope", text: "照準を読む")
                    TrainingRule(icon: "bolt.fill", text: "反応を磨く")
                }

                GamePrimaryButton(
                    title: "バトル開始",
                    subtitle: "TAP TO ENTER THE ARENA",
                    systemImage: "arrow.right",
                    action: onStart
                )
            }
            .padding(22)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 24)
    }

    private var formattedBestTime: String {
        guard bestSurvivalTime > 0 else { return "—" }
        return String(format: "%.1fs", bestSurvivalTime)
    }
}

private struct CharacterStage: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.30))
                .frame(width: 145, height: 42)
                .offset(y: 95)
                .blur(radius: 4)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [GameTheme.cyan.opacity(0.25), GameTheme.plum.opacity(0.08), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 95
                    )
                )
                .overlay {
                    Circle()
                        .stroke(GameTheme.cyan.opacity(0.22), lineWidth: 1)
                        .padding(16)
                }

            Image(uiImage: PlayerNode.menuPortraitImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 178)
                .shadow(color: .black.opacity(0.48), radius: 14, y: 10)
        }
    }
}

private struct TrainingRule: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(GameTheme.cyan)
            Text(text)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

#Preview("Landscape") {
    HomeView(bestSurvivalTime: 41.7, bestDodgedCount: 93, onStart: {})
        .frame(width: 932, height: 430)
}

#Preview("Portrait") {
    HomeView(bestSurvivalTime: 41.7, bestDodgedCount: 93, onStart: {})
}
