import Foundation

enum GameMode: Equatable {
    case practice
    case ranked
}

enum RankingRules {
    static let version = 1
    static let fixedSeed = UUID(uuidString: "5350494B-4544-4F44-4745-52414E4B3031")!
    static let playerSpeed: PlayerSpeedSetting = .normal
}

struct RankingSeason: Identifiable, Hashable {
    static let firstYear = 2026
    static let firstMonth = 8
    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    let number: Int
    let year: Int
    let month: Int

    var id: String { "v\(number)" }

    var localizedLabel: String {
        L10n.format("ranking.season.label", number, String(year), month)
    }

    static var current: RankingSeason {
        season(containing: Date())
    }

    static var available: [RankingSeason] {
        let latest = current.number
        guard latest >= 1 else { return [] }
        return (1...latest).reversed().compactMap(season(number:))
    }

    static func season(containing date: Date) -> RankingSeason {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? firstYear
        let month = components.month ?? firstMonth
        let number = (year - firstYear) * 12 + month - firstMonth + 1
        return RankingSeason(number: max(1, number), year: year, month: month)
    }

    static func season(number: Int) -> RankingSeason? {
        guard number >= 1 else { return nil }
        let zeroBasedMonth = firstMonth - 1 + number - 1
        return RankingSeason(
            number: number,
            year: firstYear + zeroBasedMonth / 12,
            month: zeroBasedMonth % 12 + 1
        )
    }
}

enum ProfileIcon: String, CaseIterable, Identifiable, Codable {
    case crown, shield, curve, bolt, star, orbit
    case flame, diamond, target, heart, moon, paw
    case seasonChampion = "season_champion"
    case seasonChampion2 = "season_champion_2"
    case seasonChampion3 = "season_champion_3"
    case seasonChampion4 = "season_champion_4"
    case seasonChampion5 = "season_champion_5"
    case developerRainbow = "developer_rainbow"

    var id: String { rawValue }

    static var standardCases: [ProfileIcon] {
        allCases.filter { !$0.isLimited }
    }

    var assetName: String? {
        isLimited ? rawValue : nil
    }

    var isLimited: Bool {
        switch self {
        case .seasonChampion, .seasonChampion2, .seasonChampion3,
             .seasonChampion4, .seasonChampion5, .developerRainbow:
            true
        default:
            false
        }
    }

    var symbolName: String {
        switch self {
        case .crown: "crown.fill"
        case .shield: "shield.fill"
        case .curve: "arrow.trianglehead.2.clockwise.rotate.90"
        case .bolt: "bolt.fill"
        case .star: "star.fill"
        case .orbit: "circle.hexagongrid.fill"
        case .flame: "flame.fill"
        case .diamond: "diamond.fill"
        case .target: "scope"
        case .heart: "heart.fill"
        case .moon: "moon.stars.fill"
        case .paw: "pawprint.fill"
        case .seasonChampion, .seasonChampion2, .seasonChampion3,
             .seasonChampion4, .seasonChampion5, .developerRainbow:
            "crown.fill"
        }
    }
}

struct RankingProfile: Equatable {
    let uid: String
    let displayName: String
    let nameKey: String
    let icon: ProfileIcon
    let unlockedIcons: Set<ProfileIcon>

    var availableIcons: [ProfileIcon] {
        ProfileIcon.allCases.filter { icon in
            ProfileIcon.standardCases.contains(icon) || unlockedIcons.contains(icon)
        }
    }
}

struct LeaderboardEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
    let icon: ProfileIcon
    let survivalMilliseconds: Int
    let dodgedCount: Int

    var survivalTime: TimeInterval { TimeInterval(survivalMilliseconds) / 1_000 }
}

enum RankingSubmissionState: Equatable {
    case idle
    case submitting
    case submitted(isPersonalBest: Bool)
    case failed(String)
}

enum RankingNameValidator {
    static func normalizedDisplayName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
    }

    static func key(for displayName: String) -> String {
        normalizedDisplayName(displayName)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func isValid(_ displayName: String) -> Bool {
        let name = normalizedDisplayName(displayName)
        guard (2...12).contains(name.count) else { return false }
        return name.unicodeScalars.allSatisfy(isAllowed)
    }

    private nonisolated static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, // ASCII letters and numbers
             0x3041...0x3096,                         // Hiragana
             0x30A1...0x30FA, 0x30FC,                 // Katakana and long vowel mark
             0x4E00...0x9FFF, 0x3005:                 // CJK and iteration mark
            return true
        default:
            return false
        }
    }
}
