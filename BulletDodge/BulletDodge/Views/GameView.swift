import SpriteKit
import SwiftUI

struct GameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionStore: GameSessionStore
    @State private var scene: GameScene
    private let gameMode: GameMode
    private let hideHUD = ProcessInfo.processInfo.environment["BULLETDODGE_HIDE_HUD"] == "1"

    init(
        seed: UUID,
        joystickMode: JoystickMode,
        playerSpeedSetting: PlayerSpeedSetting,
        dodgeGuideEnabled: Bool,
        gameMode: GameMode,
        onGameOver: @escaping (GameResult) -> Void
    ) {
        self.gameMode = gameMode
        let store = GameSessionStore()
        _sessionStore = StateObject(wrappedValue: store)
        _scene = State(
            initialValue: GameScene(
                seed: seed,
                joystickMode: joystickMode,
                playerSpeedSetting: playerSpeedSetting,
                dodgeGuideEnabled: dodgeGuideEnabled,
                attackRules: gameMode == .ranked
                    ? RankingRules.attackRules(for: .current)
                    : .legacy,
                sessionStore: store,
                onGameOver: onGameOver
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let usesTabletBattleViewport = UIDevice.current.userInterfaceIdiom == .pad
            let viewportSize = BattleViewport.size(
                fitting: geometry.size,
                usesTabletBattleViewport: usesTabletBattleViewport
            )

            ZStack {
                Color.black

                ZStack(alignment: .topTrailing) {
                    SpriteView(
                        scene: scene,
                        preferredFramesPerSecond: 120,
                        options: [.ignoresSiblingOrder]
                    )
                    .background(Color.black)

                    if !hideHUD {
                        survivalTimeHUD
                            .padding(
                                .top,
                                usesTabletBattleViewport
                                    ? 10
                                    : geometry.safeAreaInsets.top + 10
                            )
                            .padding(.trailing, 12)
                    }
                }
                .frame(width: viewportSize.width, height: viewportSize.height)
                .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    scene.setPaused(true)
                }
            }
        }
        .statusBarHidden(true)
    }

    private var survivalTimeHUD: some View {
        HStack(spacing: 10) {
            if gameMode == .ranked {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(GameTheme.gold)
                    .accessibilityLabel(L10n.text("ranking.mode"))
            }
            Text(currentRankLetter)
                .font(.system(
                    size: currentRankLetter.count >= 3 ? 13 : (currentRankLetter.count == 2 ? 16 : 20),
                    weight: .black,
                    design: .serif
                ))
                .foregroundStyle(rankAccent)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.32), in: Circle())
                .overlay {
                    Circle()
                        .stroke(rankAccent.opacity(0.88), lineWidth: 2)
                }

            Capsule()
                .fill(GameTheme.cyan)
                .frame(width: 3, height: 24)

            Text(L10n.format("format.seconds_short", sessionStore.snapshot.survivalTime))
                .font(.system(size: 25, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.leading, 9)
        .padding(.trailing, 13)
        .padding(.vertical, 7)
        .frame(minWidth: 138, alignment: .trailing)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 5, y: 2)
        .allowsHitTesting(false)
        .accessibilityLabel(
            "\(L10n.format("accessibility.rank", currentRankLetter)), "
                + L10n.format("format.seconds_short", sessionStore.snapshot.survivalTime)
        )
    }

    private var currentRankLetter: String {
        PerformanceRank(survivalTime: sessionStore.snapshot.survivalTime).rawValue
    }

    private var rankAccent: Color {
        switch PerformanceRank(survivalTime: sessionStore.snapshot.survivalTime).tier {
        case .sss: Color(red: 0.95, green: 0.28, blue: 0.50)
        case .ss: GameTheme.violet
        case .s: GameTheme.gold
        case .a: GameTheme.mint
        case .b: GameTheme.cyan
        case .c: GameTheme.coral
        case .d: GameTheme.softText
        }
    }
}

private enum BattleViewport {
    /// Brawl-style tablet presentation: keep the authored battle projection in
    /// a centered 16:9 viewport and letterbox the unused tablet height. The
    /// scene camera preserves the iPhone render scale and crops only the sides,
    /// while gameplay coordinates and collision logic remain device-independent.
    private static let tabletAspectRatio: CGFloat = 16.0 / 9.0

    static func size(
        fitting containerSize: CGSize,
        usesTabletBattleViewport: Bool
    ) -> CGSize {
        guard usesTabletBattleViewport,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        let containerAspectRatio = containerSize.width / containerSize.height
        if containerAspectRatio > tabletAspectRatio {
            return CGSize(
                width: containerSize.height * tabletAspectRatio,
                height: containerSize.height
            )
        }

        return CGSize(
            width: containerSize.width,
            height: containerSize.width / tabletAspectRatio
        )
    }
}
