import Foundation

enum PerformanceRank: String, CaseIterable, Codable, Identifiable {
    case ss = "SS"
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var id: String { rawValue }

    init(survivalTime: TimeInterval) {
        switch survivalTime {
        case 68...: self = .ss
        case 45...: self = .s
        case 35...: self = .a
        case 20...: self = .b
        case 10...: self = .c
        default: self = .d
        }
    }
}

struct GameRunRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let playedAt: Date
    let survivalTime: TimeInterval
    let dodgedCount: Int
    let hitCount: Int
    let playerSpeedSetting: PlayerSpeedSetting

    init(result: GameResult, playedAt: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.playedAt = playedAt
        survivalTime = result.survivalTime
        dodgedCount = result.dodgedCount
        hitCount = result.hitCount
        playerSpeedSetting = result.playerSpeedSetting
    }

    var rank: PerformanceRank {
        PerformanceRank(survivalTime: survivalTime)
    }

    var avoidanceRate: Double {
        let total = dodgedCount + hitCount
        guard total > 0 else { return 0 }
        return Double(dodgedCount) / Double(total)
    }
}

struct SpeedProgress: Codable, Equatable {
    var playCount = 0
    var totalSurvivalTime: TimeInterval = 0
    var bestSurvivalTime: TimeInterval = 0
    var bestDodgedCount = 0

    mutating func record(_ result: GameResult) {
        playCount += 1
        totalSurvivalTime += result.survivalTime
        bestSurvivalTime = max(bestSurvivalTime, result.survivalTime)
        bestDodgedCount = max(bestDodgedCount, result.dodgedCount)
    }
}

struct PlayerProgress: Codable, Equatable {
    private static let maximumRecentRuns = 40

    var totalRuns = 0
    var totalSurvivalTime: TimeInterval = 0
    var totalDodgedCount = 0
    var totalHitCount = 0
    var rankCounts: [String: Int] = [:]
    var speedProgress: [String: SpeedProgress] = [:]
    var recentRuns: [GameRunRecord] = []

    static let empty = PlayerProgress()

    mutating func record(_ result: GameResult, playedAt: Date = Date()) {
        totalRuns += 1
        totalSurvivalTime += result.survivalTime
        totalDodgedCount += result.dodgedCount
        totalHitCount += result.hitCount

        let rank = PerformanceRank(survivalTime: result.survivalTime)
        rankCounts[rank.rawValue, default: 0] += 1

        var speed = speedProgress[result.playerSpeedSetting.rawValue] ?? SpeedProgress()
        speed.record(result)
        speedProgress[result.playerSpeedSetting.rawValue] = speed

        recentRuns.append(GameRunRecord(result: result, playedAt: playedAt))
        if recentRuns.count > Self.maximumRecentRuns {
            recentRuns.removeFirst(recentRuns.count - Self.maximumRecentRuns)
        }
    }

    var averageSurvivalTime: TimeInterval {
        guard totalRuns > 0 else { return 0 }
        return totalSurvivalTime / Double(totalRuns)
    }

    var overallAvoidanceRate: Double {
        let attempts = totalDodgedCount + totalHitCount
        guard attempts > 0 else { return 0 }
        return Double(totalDodgedCount) / Double(attempts)
    }

    var recentTenRuns: [GameRunRecord] {
        Array(recentRuns.suffix(10))
    }

    var recentTenAverage: TimeInterval {
        Self.average(of: recentTenRuns)
    }

    var previousTenAverage: TimeInterval {
        let end = max(0, recentRuns.count - 10)
        let start = max(0, end - 10)
        return Self.average(of: Array(recentRuns[start..<end]))
    }

    var averageImprovement: TimeInterval? {
        guard recentRuns.count >= 11 else { return nil }
        return recentTenAverage - previousTenAverage
    }

    func count(for rank: PerformanceRank) -> Int {
        rankCounts[rank.rawValue] ?? 0
    }

    func progress(for speed: PlayerSpeedSetting) -> SpeedProgress {
        speedProgress[speed.rawValue] ?? SpeedProgress()
    }

    private static func average(of runs: [GameRunRecord]) -> TimeInterval {
        guard !runs.isEmpty else { return 0 }
        return runs.reduce(0) { $0 + $1.survivalTime } / Double(runs.count)
    }
}

#if DEBUG
extension PlayerProgress {
    static var preview: PlayerProgress {
        let times: [TimeInterval] = [
            12.8, 18.6, 16.9, 24.2, 22.7, 28.4, 31.8, 29.6, 37.1, 34.5,
            41.2, 38.8, 46.3, 43.9, 52.4, 48.7, 57.6, 54.1, 63.8, 70.4
        ]
        var value = PlayerProgress.empty
        for (index, time) in times.enumerated() {
            let speed = PlayerSpeedSetting.allCases[index % PlayerSpeedSetting.allCases.count]
            let result = GameResult(
                survivalTime: time,
                dodgedCount: Int(time * 2.05),
                hitCount: max(1, 5 - index / 5),
                playerSpeedSetting: speed
            )
            value.record(
                result,
                playedAt: Calendar.current.date(
                    byAdding: .day,
                    value: index - times.count,
                    to: Date()
                ) ?? Date()
            )
        }
        return value
    }
}
#endif
