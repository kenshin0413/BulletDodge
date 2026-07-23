import SwiftUI

struct ContentView: View {
    @StateObject private var saveManager = SaveManager()
    @State private var phase: AppPhase = DebugLaunchOptions.autoStartGame ? .playing : .home
    @State private var latestResult: GameResult?
    @State private var gameSeed = UUID()
    @State private var didSetTimeRecord = false
    @State private var didSetDodgedRecord = false

    var body: some View {
        ZStack {
            switch phase {
            case .home:
                HomeView(
                    bestSurvivalTime: saveManager.bestSurvivalTime,
                    bestDodgedCount: saveManager.bestDodgedCount,
                    onStart: startGame
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case .playing:
                GameView(seed: gameSeed) { result in
                    didSetTimeRecord = result.survivalTime > saveManager.bestSurvivalTime
                    didSetDodgedRecord = result.dodgedCount > saveManager.bestDodgedCount
                    latestResult = result
                    saveManager.updateBestRecords(with: result)
                    phase = .result
                }
                .transition(.opacity)
            case .result:
                if let latestResult {
                    ResultView(
                        result: latestResult,
                        bestSurvivalTime: saveManager.bestSurvivalTime,
                        bestDodgedCount: saveManager.bestDodgedCount,
                        didSetTimeRecord: didSetTimeRecord,
                        didSetDodgedRecord: didSetDodgedRecord,
                        onRetry: startGame,
                        onHome: { phase = .home }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phase)
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
