import SwiftUI
import StoreKit
import Combine

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    @ObservedObject var advertisingConsentManager: AdvertisingConsentManager

    @StateObject private var saveManager = SaveManager()
    @StateObject private var updateChecker = AppUpdateChecker()
    @StateObject private var interstitialAdManager = InterstitialAdManager()
    @StateObject private var rewardedAdManager = RewardedAdManager()
    @StateObject private var rewardAccessManager = RewardAccessManager()
    @StateObject private var rankingService = RankingService()
    @State private var reviewPromptPolicy = ReviewPromptPolicy()
    @State private var phase: AppPhase = DebugLaunchOptions.initialPhase
    @State private var latestResult: GameResult? = DebugLaunchOptions.previewResult
    @State private var gameSeed = UUID()
    @State private var gameMode: GameMode = DebugLaunchOptions.previewGameMode
    @State private var isStartingRankedGame = false
    @State private var didSetTimeRecord = false
    @State private var didSetDodgedRecord = false
    @State private var reviewRequestTask: Task<Void, Never>?
    @State private var isShowingRankedRewardPrompt = ProcessInfo.processInfo.environment[
        "BULLETDODGE_SHOW_RANKED_REWARD_PROMPT"
    ] == "1"
    @State private var rewardedAdMessage: String?
    @State private var presentsPersonalBestPlacement = false

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
                    dodgeGuideEnabled: saveManager.dodgeGuideEnabled,
                    onDodgeGuideEnabledChange: saveManager.setDodgeGuideEnabled,
                    isPrivacyOptionsRequired: advertisingConsentManager.isPrivacyOptionsRequired,
                    onShowPrivacyOptions: {
                        Task {
                            await advertisingConsentManager.presentPrivacyOptions()
                        }
                    },
                    rankingProfile: rankingService.profile,
                    rankedRunsRemaining: rewardAccessManager.remainingRankedRuns,
                    onShowAccount: showAccount,
                    onShowLeaderboard: showLeaderboard,
                    onStartRanked: requestRankedGame,
                    onStart: startPracticeGame
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case .account:
                AccountView(
                    service: rankingService,
                    rewardAccessManager: rewardAccessManager,
                    rewardedAdManager: rewardedAdManager,
                    progress: saveManager.playerProgress,
                    bestSurvivalTime: saveManager.bestSurvivalTime,
                    bestDodgedCount: saveManager.bestDodgedCount,
                    onClose: showHome
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case .leaderboard:
                LeaderboardView(
                    service: rankingService,
                    rankedRunsRemaining: rewardAccessManager.remainingRankedRuns,
                    presentsPersonalBestPlacement: presentsPersonalBestPlacement,
                    onPlayRanked: requestRankedGame,
                    onCreateAccount: showAccount,
                    onClose: showHome
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case .playing:
                GameView(
                    seed: gameSeed,
                    joystickMode: saveManager.joystickMode,
                    playerSpeedSetting: gameMode == .ranked ? RankingRules.playerSpeed : saveManager.playerSpeedSetting,
                    dodgeGuideEnabled: gameMode == .practice && saveManager.dodgeGuideEnabled,
                    gameMode: gameMode
                ) { result in
                    didSetTimeRecord = result.survivalTime > saveManager.bestSurvivalTime
                    didSetDodgedRecord = result.dodgedCount > saveManager.bestDodgedCount
                    latestResult = result
                    saveManager.updateBestRecords(with: result)
                    if gameMode == .ranked {
                        Task { await rankingService.submit(result: result) }
                    }
                    finishGame(
                        showInterstitial: gameMode == .practice
                            && saveManager.registerPlayForInterstitial()
                    )
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
                        isRankedResult: gameMode == .ranked,
                        rankingShareContext: rankingShareContext,
                        onRetry: retryGame,
                        onHome: handleResultHome
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))

                    if gameMode == .ranked {
                        rankedResultBadge
                    }
                }
            }

            if isStartingRankedGame {
                Color.black.opacity(0.54).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().tint(.white).scaleEffect(1.35)
                    Text(L10n.text("ranking.preparing"))
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phase)
        .task {
            await rankingService.prepare()
            await updateChecker.checkForUpdate()
#if DEBUG
            if ProcessInfo.processInfo.environment[
                "BULLETDODGE_EXPORT_RANKED_SHARE_PREVIEW"
            ] == "1",
               let latestResult,
               let rankingShareContext,
               let image = RankingShareRenderer.render(
                    result: latestResult,
                    context: rankingShareContext
               ),
               let data = image.pngData(),
               let documents = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
               ).first {
                try? data.write(to: documents.appendingPathComponent("ranking-share-preview.png"))
            }
            if ProcessInfo.processInfo.environment["BULLETDODGE_SHOW_REVIEW_ALERT"] == "1" {
                try? await Task.sleep(for: .seconds(1))
                requestReview()
            }
#endif
        }
        .onChange(of: advertisingConsentManager.canRequestAds, initial: true) { _, canRequestAds in
            interstitialAdManager.setAdRequestAllowed(canRequestAds)
            rewardedAdManager.setAdRequestAllowed(canRequestAds)
        }
        .onChange(of: advertisingConsentManager.consentRevision) { _, _ in
            interstitialAdManager.consentDidChange()
            rewardedAdManager.consentDidChange()
        }
        .onReceive(
            Timer.publish(every: 30, on: .main, in: .common).autoconnect()
        ) { _ in
            rewardAccessManager.refreshDailyWindowIfNeeded()
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
        .alert(
            L10n.text("ranking.error.title"),
            isPresented: Binding(
                get: { rankingService.lastError != nil },
                set: { if !$0 { rankingService.clearError() } }
            )
        ) {
            Button(L10n.text("common.ok")) { rankingService.clearError() }
        } message: {
            Text(rankingService.lastError ?? "")
        }
        .alert(
            L10n.text("ranking.reward.title"),
            isPresented: $isShowingRankedRewardPrompt
        ) {
            Button(L10n.text("common.cancel"), role: .cancel) {}
            Button(L10n.text("ranking.reward.watch")) {
                rewardAccessManager.confirmRankedRewardExplanation()
                watchRewardForRankedRuns()
            }
        } message: {
            Text(L10n.text("ranking.reward.message"))
        }
        .alert(
            L10n.text("reward.error.title"),
            isPresented: Binding(
                get: { rewardedAdMessage != nil },
                set: { if !$0 { rewardedAdMessage = nil } }
            )
        ) {
            Button(L10n.text("common.ok")) { rewardedAdMessage = nil }
        } message: {
            Text(rewardedAdMessage ?? "")
        }
    }

    private func startPracticeGame() {
        reviewRequestTask?.cancel()
        gameMode = .practice
        gameSeed = UUID()
        phase = .playing
    }

    private func requestRankedGame() {
        reviewRequestTask?.cancel()
        guard rankingService.profile != nil else {
            phase = .account
            return
        }

        let access = rewardAccessManager.rankedAccessSnapshot()
        guard !access.requiresReward else {
            if rewardAccessManager.hasConfirmedRankedReward {
                watchRewardForRankedRuns()
            } else {
                isShowingRankedRewardPrompt = true
            }
            return
        }
        Task { await startRankedGame() }
    }

    private func watchRewardForRankedRuns() {
        rewardedAdManager.present { outcome in
            switch outcome {
            case .earned:
                rewardAccessManager.grantRankedRunBlock()
                Task { await startRankedGame() }
            case .unavailable:
                rewardedAdMessage = L10n.text("reward.error.unavailable")
            case .dismissedWithoutReward:
                rewardedAdMessage = L10n.text("reward.error.not_completed")
            case .failedToPresent:
                rewardedAdMessage = L10n.text("reward.error.failed")
            }
        }
    }

    private func startRankedGame() async {
        isStartingRankedGame = true
        defer { isStartingRankedGame = false }
        do {
            try await rankingService.beginRankedRun()
            guard rewardAccessManager.consumeRankedRun() else {
                rewardedAdMessage = L10n.text("ranking.reward.required")
                return
            }
            gameMode = .ranked
            gameSeed = RankingRules.fixedSeed
            phase = .playing
        } catch {
            rankingService.report(error)
        }
    }

    private func retryGame() {
        if gameMode == .ranked { requestRankedGame() } else { startPracticeGame() }
    }

    private func showLeaderboard() {
        reviewRequestTask?.cancel()
        presentsPersonalBestPlacement = false
        phase = .leaderboard
    }

    private func handleResultHome() {
        guard gameMode == .ranked else {
            showHome()
            return
        }

        Task {
            // The Firestore transaction may still be finishing when Home is
            // tapped. Only route into the placement reveal after the server has
            // confirmed that this run is a new ranked personal best.
            for _ in 0..<200 {
                switch rankingService.submissionState {
                case .submitted(let isPersonalBest):
                    guard isPersonalBest else {
                        showHome()
                        return
                    }
                    presentsPersonalBestPlacement = true
                    phase = .leaderboard
                    return
                case .failed:
                    showHome()
                    return
                case .idle, .submitting:
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            showHome()
        }
    }

    private func showHome() {
        reviewRequestTask?.cancel()
        presentsPersonalBestPlacement = false
        phase = .home
    }

    private func showAccount() {
        reviewRequestTask?.cancel()
        phase = .account
    }

    private func finishGame(showInterstitial: Bool) {
        guard showInterstitial else {
            showResult()
            return
        }

        interstitialAdManager.presentIfAvailable {
            showResult()
        }
    }

    private func showResult() {
        phase = .result
        scheduleReviewRequestIfNeeded()
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

    private var rankedResultBadge: some View {
        VStack {
            HStack {
                Spacer()
                Group {
                    switch rankingService.submissionState {
                    case .idle, .submitting:
                        Label(L10n.text("ranking.submitting"), systemImage: "icloud.and.arrow.up")
                    case .submitted(let isBest):
                        Label(
                            L10n.text(isBest ? "ranking.new_personal_best" : "ranking.submitted"),
                            systemImage: isBest ? "trophy.fill" : "checkmark.circle.fill"
                        )
                    case .failed:
                        Label(L10n.text("ranking.submit_failed"), systemImage: "exclamationmark.triangle.fill")
                    }
                }
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.black.opacity(0.76), in: Capsule())
                .padding(20)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var rankingShareContext: RankingShareContext? {
        guard gameMode == .ranked,
              let profile = rankingService.profile,
              case .submitted(let isPersonalBest) = rankingService.submissionState else {
            return nil
        }
        let worldRank = rankingService.leaderboard.firstIndex {
            $0.id == profile.uid
        }.map { $0 + 1 }
        return RankingShareContext(
            playerName: profile.displayName,
            profileIcon: profile.icon,
            worldRank: worldRank,
            season: rankingService.currentSeason,
            isPersonalBest: isPersonalBest
        )
    }
}

private enum DebugLaunchOptions {
    static let showResult = ProcessInfo.processInfo.environment["BULLETDODGE_SHOW_RESULT"] == "1"
    static let showLeaderboard = ProcessInfo.processInfo.environment["BULLETDODGE_SHOW_LEADERBOARD"] == "1"
    static let showAccount = ProcessInfo.processInfo.environment[
        "BULLETDODGE_SHOW_ACCOUNT"
    ] == "1"
    static let autoStartGame = ProcessInfo.processInfo.environment["BULLETDODGE_AUTO_START"] == "1"
    static let showRankedSharePreview = ProcessInfo.processInfo.environment[
        "BULLETDODGE_SHOW_RANKED_SHARE_PREVIEW"
    ] == "1"
    static let previewGameMode: GameMode = showRankedSharePreview ? .ranked : .practice
    static let initialPhase: AppPhase = showAccount
        ? .account
        : (showLeaderboard
            ? .leaderboard
            : (showResult ? .result : (autoStartGame ? .playing : .home)))
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
    case account
    case leaderboard
    case playing
    case result
}

#Preview {
    ContentView(advertisingConsentManager: AdvertisingConsentManager())
}
