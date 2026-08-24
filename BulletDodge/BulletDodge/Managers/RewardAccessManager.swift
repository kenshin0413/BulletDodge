import Combine
import Foundation

struct RankedAccessSnapshot: Equatable {
    let runsUsed: Int
    let totalAllowance: Int

    var remainingRuns: Int { max(0, totalAllowance - runsUsed) }
    var requiresReward: Bool { remainingRuns == 0 }
}

enum RewardAccessPolicy {
    static let freeRankedRuns = 3
    static let rewardedRankedRuns = 3
    static let dailyResetHour = 17

    static func windowStart(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let todayReset = calendar.date(
            byAdding: .hour,
            value: dailyResetHour,
            to: startOfDay
        ) ?? startOfDay

        if date >= todayReset { return todayReset }
        return calendar.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset
    }

    static func totalAllowance(rewardedBlocks: Int) -> Int {
        freeRankedRuns + max(0, rewardedBlocks) * rewardedRankedRuns
    }
}

/// Persists rewards separately from the ranking profile so an earned reward is
/// never lost when a network update fails or the app is relaunched.
@MainActor
final class RewardAccessManager: ObservableObject {
    @Published private(set) var hasNameChangeCredit: Bool
    @Published private(set) var rankedRunsUsed: Int
    @Published private(set) var rankedRewardedBlocks: Int
    @Published private(set) var hasConfirmedNameChangeReward: Bool
    @Published private(set) var hasConfirmedRankedReward: Bool

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private let nameChangeCreditKey = "reward.nameChangeCredit.v1"
    private let rankedWindowStartKey = "reward.ranked.windowStart.v1"
    private let rankedRunsUsedKey = "reward.ranked.runsUsed.v1"
    private let rankedRewardedBlocksKey = "reward.ranked.blocks.v1"
    private let nameChangeRewardConfirmedKey = "reward.nameChange.confirmed.v1"
    private let rankedRewardConfirmedKey = "reward.ranked.confirmed.v1"

    var remainingRankedRuns: Int {
        RankedAccessSnapshot(
            runsUsed: rankedRunsUsed,
            totalAllowance: RewardAccessPolicy.totalAllowance(
                rewardedBlocks: rankedRewardedBlocks
            )
        ).remainingRuns
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        hasNameChangeCredit = defaults.bool(forKey: nameChangeCreditKey)
        rankedRunsUsed = max(0, defaults.integer(forKey: rankedRunsUsedKey))
        rankedRewardedBlocks = max(0, defaults.integer(forKey: rankedRewardedBlocksKey))
        hasConfirmedNameChangeReward = defaults.bool(
            forKey: nameChangeRewardConfirmedKey
        )
        hasConfirmedRankedReward = defaults.bool(forKey: rankedRewardConfirmedKey)
        refreshDailyWindowIfNeeded()
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "BULLETDODGE_REWARD_PREVIEW_EXHAUSTED"
        ] == "1" {
            rankedRunsUsed = RewardAccessPolicy.totalAllowance(
                rewardedBlocks: rankedRewardedBlocks
            )
        }
#endif
    }

    func grantNameChangeCredit() {
        guard !hasNameChangeCredit else { return }
        hasNameChangeCredit = true
        defaults.set(true, forKey: nameChangeCreditKey)
    }

    func consumeNameChangeCredit() {
        guard hasNameChangeCredit else { return }
        hasNameChangeCredit = false
        defaults.set(false, forKey: nameChangeCreditKey)
    }

    func confirmNameChangeRewardExplanation() {
        guard !hasConfirmedNameChangeReward else { return }
        hasConfirmedNameChangeReward = true
        defaults.set(true, forKey: nameChangeRewardConfirmedKey)
    }

    func confirmRankedRewardExplanation() {
        guard !hasConfirmedRankedReward else { return }
        hasConfirmedRankedReward = true
        defaults.set(true, forKey: rankedRewardConfirmedKey)
    }

    @discardableResult
    func rankedAccessSnapshot() -> RankedAccessSnapshot {
        refreshDailyWindowIfNeeded()
        return RankedAccessSnapshot(
            runsUsed: rankedRunsUsed,
            totalAllowance: RewardAccessPolicy.totalAllowance(
                rewardedBlocks: rankedRewardedBlocks
            )
        )
    }

    func grantRankedRunBlock() {
        refreshDailyWindowIfNeeded()
        rankedRewardedBlocks += 1
        defaults.set(rankedRewardedBlocks, forKey: rankedRewardedBlocksKey)
    }

    @discardableResult
    func consumeRankedRun() -> Bool {
        let snapshot = rankedAccessSnapshot()
        guard snapshot.remainingRuns > 0 else { return false }
        rankedRunsUsed += 1
        defaults.set(rankedRunsUsed, forKey: rankedRunsUsedKey)
        return true
    }

    func refreshDailyWindowIfNeeded() {
        let currentWindowStart = RewardAccessPolicy.windowStart(
            for: now(),
            calendar: calendar
        )
        let storedWindowStart = defaults.object(forKey: rankedWindowStartKey) as? Date

        guard storedWindowStart == currentWindowStart else {
            rankedRunsUsed = 0
            rankedRewardedBlocks = 0
            defaults.set(currentWindowStart, forKey: rankedWindowStartKey)
            defaults.set(0, forKey: rankedRunsUsedKey)
            defaults.set(0, forKey: rankedRewardedBlocksKey)
            return
        }
    }
}
