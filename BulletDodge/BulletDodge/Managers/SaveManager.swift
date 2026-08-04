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

    private let defaults = UserDefaults.standard
    private let bestSurvivalTimeKey = "bestSurvivalTime"
    private let bestDodgedCountKey = "bestDodgedCount"
    private let joystickModeKey = "joystickMode"
    private let playerSpeedSettingKey = "playerSpeedSetting"

    init() {
        bestSurvivalTime = defaults.double(forKey: bestSurvivalTimeKey)
        bestDodgedCount = defaults.integer(forKey: bestDodgedCountKey)
        joystickMode = JoystickMode(
            rawValue: defaults.string(forKey: joystickModeKey) ?? ""
        ) ?? .fixed
        playerSpeedSetting = PlayerSpeedSetting(
            rawValue: defaults.string(forKey: playerSpeedSettingKey) ?? ""
        ) ?? .normal
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
}
