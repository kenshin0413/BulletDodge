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
                    compactHUD
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                        .padding(.trailing, 10)
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

    private var compactHUD: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(action: { scene.setPaused(!scene.isGamePaused) }) {
                Text(scene.isGamePaused ? "再開" : "停止")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.28))
                    .foregroundStyle(.white.opacity(0.92))
                    .clipShape(Capsule())
            }

            VStack(alignment: .trailing, spacing: 4) {
                hpMiniBar

                HStack(spacing: 6) {
                    MiniStat(text: String(format: "%.1fs", sessionStore.snapshot.survivalTime))
                    MiniStat(text: "D \(sessionStore.snapshot.dodgedCount)")
                    MiniStat(text: "H \(sessionStore.snapshot.hitCount)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.black.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var hpMiniBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.22))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.31, green: 0.84, blue: 0.54), Color(red: 0.13, green: 0.58, blue: 0.97)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * sessionStore.snapshot.hpRatio)
            }
        }
        .frame(width: 132, height: 8)
    }
}

private struct MiniStat: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.white.opacity(0.07))
            .clipShape(Capsule())
    }
}
