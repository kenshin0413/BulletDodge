import Foundation
import Combine

enum JoystickMode: String, CaseIterable, Identifiable {
    case fixed
    case floating

    var id: String { rawValue }
}

enum PlayerSpeedSetting: String, CaseIterable, Identifiable, Codable {
    case slow
    case normal
    case fast
    case ultraFast

    var id: String { rawValue }
}

@MainActor
final class SaveManager: ObservableObject {
    @Published private(set) var bestSurvivalTime: TimeInterval
    @Published private(set) var bestDodgedCount: Int
    @Published private(set) var joystickMode: JoystickMode
    @Published private(set) var playerSpeedSetting: PlayerSpeedSetting
    @Published private(set) var dodgeGuideEnabled: Bool
    @Published private(set) var playerProgress: PlayerProgress

    private let defaults = UserDefaults.standard
    private let bestSurvivalTimeKey = "bestSurvivalTime"
    private let bestDodgedCountKey = "bestDodgedCount"
    private let joystickModeKey = "joystickMode"
    private let playerSpeedSettingKey = "playerSpeedSetting"
    private let dodgeGuideEnabledKey = "dodgeGuideEnabled"
    private let playerProgressKey = "playerProgress.v1"
    private let interstitialPlayCountKey = "interstitialPlayCount"

    init() {
        bestSurvivalTime = defaults.double(forKey: bestSurvivalTimeKey)
        bestDodgedCount = defaults.integer(forKey: bestDodgedCountKey)
        joystickMode = JoystickMode(
            rawValue: defaults.string(forKey: joystickModeKey) ?? ""
        ) ?? .fixed
        playerSpeedSetting = PlayerSpeedSetting(
            rawValue: defaults.string(forKey: playerSpeedSettingKey) ?? ""
        ) ?? .normal
        dodgeGuideEnabled = defaults.bool(forKey: dodgeGuideEnabledKey)
        if let data = defaults.data(forKey: playerProgressKey),
           let savedProgress = try? JSONDecoder().decode(PlayerProgress.self, from: data) {
            playerProgress = savedProgress
        } else {
            playerProgress = .empty
        }

#if DEBUG
        if ProcessInfo.processInfo.environment["BULLETDODGE_PROGRESS_PREVIEW"] == "1" {
            playerProgress = .preview
            bestSurvivalTime = max(bestSurvivalTime, 70.4)
            bestDodgedCount = max(bestDodgedCount, 144)
        }
#endif
    }

    func updateBestRecords(with result: GameResult) {
        playerProgress.record(result)
        persistPlayerProgress()

        if result.survivalTime > bestSurvivalTime {
            bestSurvivalTime = result.survivalTime
            defaults.set(result.survivalTime, forKey: bestSurvivalTimeKey)
        }

        if result.dodgedCount > bestDodgedCount {
            bestDodgedCount = result.dodgedCount
            defaults.set(result.dodgedCount, forKey: bestDodgedCountKey)
        }
    }

    func registerPlayForInterstitial() -> Bool {
        let nextCount = defaults.integer(forKey: interstitialPlayCountKey) + 1
        defaults.set(nextCount, forKey: interstitialPlayCountKey)
        return nextCount.isMultiple(of: 3)
    }

    func setJoystickMode(_ mode: JoystickMode) {
        guard joystickMode != mode else { return }
        joystickMode = mode
        defaults.set(mode.rawValue, forKey: joystickModeKey)
    }

    func setPlayerSpeedSetting(_ setting: PlayerSpeedSetting) {
        guard playerSpeedSetting != setting else { return }
        playerSpeedSetting = setting
        defaults.set(setting.rawValue, forKey: playerSpeedSettingKey)
    }

    func setDodgeGuideEnabled(_ isEnabled: Bool) {
        guard dodgeGuideEnabled != isEnabled else { return }
        dodgeGuideEnabled = isEnabled
        defaults.set(isEnabled, forKey: dodgeGuideEnabledKey)
    }

    private func persistPlayerProgress() {
        guard let data = try? JSONEncoder().encode(playerProgress) else { return }
        defaults.set(data, forKey: playerProgressKey)
    }
}
