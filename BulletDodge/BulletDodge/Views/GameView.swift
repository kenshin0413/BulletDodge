import SpriteKit
import SwiftUI

struct GameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sessionStore: GameSessionStore
    @State private var scene: GameScene
    private let hideHUD = ProcessInfo.processInfo.environment["BULLETDODGE_HIDE_HUD"] == "1"

    init(seed: UUID, onGameOver: @escaping (GameResult) -> Void) {
        let store = GameSessionStore()
        _sessionStore = StateObject(wrappedValue: store)
        _scene = State(initialValue: GameScene(seed: seed, sessionStore: store, onGameOver: onGameOver))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
                    .background(Color.black)

                if !hideHUD {
                    survivalTimeHUD
                        .padding(.top, geometry.safeAreaInsets.top + 10)
                        .padding(.trailing, 12)
                }
            }
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
            Text(currentRankLetter)
                .font(.system(size: 20, weight: .black, design: .serif))
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
        switch sessionStore.snapshot.survivalTime {
        case 45...: "S"
        case 35...: "A"
        case 20...: "B"
        default: "C"
        }
    }

    private var rankAccent: Color {
        switch currentRankLetter {
        case "S": GameTheme.gold
        case "A": GameTheme.mint
        case "B": GameTheme.cyan
        default: GameTheme.coral
        }
    }
}
