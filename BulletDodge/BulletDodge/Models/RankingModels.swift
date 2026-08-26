import Foundation

enum GameMode: Equatable {
    case practice
    case ranked
}

enum RankingRules {
    static var version: Int { version(for: .current) }
    static let fixedSeed = UUID(uuidString: "5350494B-4544-4F44-4745-52414E4B3031")!
    static let playerSpeed: PlayerSpeedSetting = .normal

    static func version(for season: RankingSeason) -> Int {
        season.number >= 2 ? 2 : 1
    }

    static func attackRules(for season: RankingSeason) -> BattleAttackRules {
        season.number >= 2 ? .seasonTwoAndLaterRanked : .legacy
    }
}

enum OfficialRankingAccounts {
    static let developerUID = "lNOc8N0menYh0CUS5aFGYH9wHXb2"

    static func isSeasonRewardExcluded(uid: String) -> Bool {
        uid == developerUID
    }
}

struct BurstWeights: Equatable {
    let single: Int
    let double: Int
    let triple: Int
}

#if DEBUG
enum RuleBoundaryChecks {
    static func run() {
        let rankCases: [(TimeInterval, PerformanceRank)] = [
            (0, .dMinus), (9.999, .dMinus), (10, .d),
            (14.999, .d), (15, .dPlus), (19.999, .dPlus),
            (20, .cMinus), (24.999, .cMinus), (25, .c),
            (29.999, .c), (30, .cPlus), (34.999, .cPlus),
            (35, .bMinus), (39.999, .bMinus), (40, .b),
            (44.999, .b), (45, .bPlus), (49.999, .bPlus),
            (50, .aMinus), (54.999, .aMinus), (55, .a),
            (59.999, .a), (60, .aPlus), (64.999, .aPlus),
            (65, .sMinus), (69.999, .sMinus), (70, .s),
            (74.999, .s), (75, .sPlus), (79.999, .sPlus),
            (80, .ssMinus), (89.999, .ssMinus), (90, .ss),
            (99.999, .ss), (100, .ssPlus), (114.999, .ssPlus),
            (115, .sss)
        ]
        for (time, expected) in rankCases {
            precondition(
                PerformanceRank(survivalTime: time) == expected,
                "Rank boundary failed at \(time) seconds"
            )
        }

        let seasonOne = RankingSeason(number: 1, year: 2026, month: 8)
        let seasonTwo = RankingSeason(number: 2, year: 2026, month: 9)
        let seasonThree = RankingSeason(number: 3, year: 2026, month: 10)
        precondition(RankingRules.version(for: seasonOne) == 1)
        precondition(RankingRules.version(for: seasonTwo) == 2)
        precondition(RankingRules.version(for: seasonThree) == 2)

        let legacy = RankingRules.attackRules(for: seasonOne)
        precondition(legacy.isHyperchargeActive(at: 35))
        precondition(legacy.isHyperchargeActive(at: 41.999))
        precondition(!legacy.isHyperchargeActive(at: 42))
        precondition(legacy.isHyperchargeActive(at: 60))
        precondition(!legacy.isHyperchargeActive(at: 67))
        precondition(!legacy.isHyperchargeActive(at: 85))

        let current = RankingRules.attackRules(for: seasonTwo)
        precondition(current.isHyperchargeActive(at: 35))
        precondition(!current.isHyperchargeActive(at: 42))
        precondition(current.isHyperchargeActive(at: 60))
        precondition(!current.isHyperchargeActive(at: 67))
        precondition(current.isHyperchargeActive(at: 85))
        precondition(!current.isHyperchargeActive(at: 92))
        precondition(current.isHyperchargeActive(at: 110))

        precondition(current.burstWeights(at: 0) == .init(single: 52, double: 33, triple: 15))
        precondition(current.burstWeights(at: 35) == .init(single: 49, double: 34, triple: 17))
        precondition(current.burstWeights(at: 60) == .init(single: 46, double: 35, triple: 19))
        precondition(current.burstWeights(at: 85) == .init(single: 43, double: 36, triple: 21))
        precondition(current.burstWeights(at: 110) == .init(single: 40, double: 37, triple: 23))
    }
}
#endif

struct BattleAttackRules {
    let repeatsHypercharge: Bool
    let usesProgressiveBursts: Bool

    static let legacy = BattleAttackRules(
        repeatsHypercharge: false,
        usesProgressiveBursts: false
    )

    static let seasonTwoAndLaterRanked = BattleAttackRules(
        repeatsHypercharge: true,
        usesProgressiveBursts: true
    )

    func isHyperchargeActive(at survivalTime: TimeInterval) -> Bool {
        guard survivalTime >= 35 else { return false }
        if !repeatsHypercharge, survivalTime >= 67 { return false }
        return (survivalTime - 35).truncatingRemainder(dividingBy: 25) < 7
    }

    func burstWeights(at survivalTime: TimeInterval) -> BurstWeights {
        guard usesProgressiveBursts else {
            return BurstWeights(single: 52, double: 33, triple: 15)
        }
        switch survivalTime {
        case 110...: return BurstWeights(single: 40, double: 37, triple: 23)
        case 85...: return BurstWeights(single: 43, double: 36, triple: 21)
        case 60...: return BurstWeights(single: 46, double: 35, triple: 19)
        case 35...: return BurstWeights(single: 49, double: 34, triple: 17)
        default: return BurstWeights(single: 52, double: 33, triple: 15)
        }
    }
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

    var endDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let start = calendar.date(
            from: DateComponents(year: year, month: month, day: 1)
        )!
        return calendar.date(byAdding: .month, value: 1, to: start)!
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
