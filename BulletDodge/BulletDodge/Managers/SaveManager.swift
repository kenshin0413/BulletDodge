import Foundation
import Combine

@MainActor
final class SaveManager: ObservableObject {
    @Published private(set) var bestSurvivalTime: TimeInterval
    @Published private(set) var bestDodgedCount: Int

    private let defaults = UserDefaults.standard
    private let bestSurvivalTimeKey = "bestSurvivalTime"
    private let bestDodgedCountKey = "bestDodgedCount"

    init() {
        bestSurvivalTime = defaults.double(forKey: bestSurvivalTimeKey)
        bestDodgedCount = defaults.integer(forKey: bestDodgedCountKey)
    }

    func updateBestRecords(with result: GameResult) {
        if result.survivalTime > bestSurvivalTime {
            bestSurvivalTime = result.survivalTime
            defaults.set(result.survivalTime, forKey: bestSurvivalTimeKey)
        }

        if result.dodgedCount > bestDodgedCount {
            bestDodgedCount = result.dodgedCount
            defaults.set(result.dodgedCount, forKey: bestDodgedCountKey)
        }
    }
}
