import SwiftUI

struct ContentView: View {
    @StateObject private var saveManager = SaveManager()
    @State private var phase: AppPhase = DebugLaunchOptions.autoStartGame ? .playing : .home
    @State private var latestResult: GameResult?
    @State private var gameSeed = UUID()

    var body: some View {
        Group {
            switch phase {
            case .home:
                HomeView(
                    bestSurvivalTime: saveManager.bestSurvivalTime,
                    bestDodgedCount: saveManager.bestDodgedCount,
                    onStart: startGame
                )
            case .playing:
                GameView(seed: gameSeed) { result in
                    latestResult = result
                    saveManager.updateBestRecords(with: result)
                    phase = .result
                }
            case .result:
                if let latestResult {
                    ResultView(
                        result: latestResult,
                        bestSurvivalTime: saveManager.bestSurvivalTime,
                        bestDodgedCount: saveManager.bestDodgedCount,
                        onRetry: startGame,
                        onHome: { phase = .home }
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    private func startGame() {
        gameSeed = UUID()
        phase = .playing
    }
}

private enum DebugLaunchOptions {
    static let autoStartGame = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_START"] == "1"
}

private enum AppPhase {
    case home
    case playing
    case result
}

#Preview {
    ContentView()
}
