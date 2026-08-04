import SwiftUI
import StoreKit

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @StateObject private var saveManager = SaveManager()
    @StateObject private var updateChecker = AppUpdateChecker()
    @State private var reviewPromptPolicy = ReviewPromptPolicy()
    @State private var phase: AppPhase = DebugLaunchOptions.initialPhase
    @State private var latestResult: GameResult? = DebugLaunchOptions.previewResult
    @State private var gameSeed = UUID()
    @State private var didSetTimeRecord = false
    @State private var didSetDodgedRecord = false
    @State private var reviewRequestTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            switch phase {
            case .home:
                HomeView(
                    bestSurvivalTime: saveManager.bestSurvivalTime,
                    bestDodgedCount: saveManager.bestDodgedCount,
                    joystickMode: saveManager.joystickMode,
                    onJoystickModeChange: saveManager.setJoystickMode,
                    playerSpeedSetting: saveManager.playerSpeedSetting,
                    onPlayerSpeedSettingChange: saveManager.setPlayerSpeedSetting,
                    onStart: startGame
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case .playing:
                GameView(
                    seed: gameSeed,
                    joystickMode: saveManager.joystickMode,
                    playerSpeedSetting: saveManager.playerSpeedSetting
                ) { result in
                    didSetTimeRecord = result.survivalTime > saveManager.bestSurvivalTime
                    didSetDodgedRecord = result.dodgedCount > saveManager.bestDodgedCount
                    latestResult = result
                    saveManager.updateBestRecords(with: result)
                    phase = .result
                    scheduleReviewRequestIfNeeded()
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
                        onHome: showHome
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phase)
        .task {
            await updateChecker.checkForUpdate()
#if DEBUG
            if ProcessInfo.processInfo.environment["BULLETDODGE_SHOW_REVIEW_ALERT"] == "1" {
                try? await Task.sleep(for: .seconds(1))
                requestReview()
            }
#endif
        }
        .alert(
            L10n.text("update.title"),
            isPresented: Binding(
                get: { phase == .home && updateChecker.availableUpdate != nil },
                set: { isPresented in
                    if !isPresented {
                        updateChecker.availableUpdate = nil
                    }
                }
            ),
            presenting: updateChecker.availableUpdate
        ) { update in
            Button(L10n.text("update.later"), role: .cancel) {
                updateChecker.availableUpdate = nil
            }
            Button(L10n.text("update.action")) {
                openURL(update.storeURL)
                updateChecker.availableUpdate = nil
            }
        } message: { update in
            Text(L10n.format("update.message", update.version))
        }
    }

    private func startGame() {
        reviewRequestTask?.cancel()
        gameSeed = UUID()
        phase = .playing
    }

    private func showHome() {
        reviewRequestTask?.cancel()
        phase = .home
    }

    private func scheduleReviewRequestIfNeeded() {
        guard reviewPromptPolicy.registerCompletion() else { return }

        reviewRequestTask?.cancel()
        reviewRequestTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, phase == .result else { return }
            reviewPromptPolicy.markRequested()
            requestReview()
        }
    }
}

private enum DebugLaunchOptions {
    static let showResult = ProcessInfo.processInfo.environment["BULLETDODGE_SHOW_RESULT"] == "1"
    static let autoStartGame = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_START"] == "1"
    static let initialPhase: AppPhase = showResult ? .result : (autoStartGame ? .playing : .home)
    static let previewResult: GameResult? = showResult
        ? GameResult(
            survivalTime: 31.4,
            dodgedCount: 62,
            hitCount: 3,
            playerSpeedSetting: .normal
        )
        : nil
}

private enum AppPhase {
    case home
    case playing
    case result
}

#Preview {
    ContentView()
}
