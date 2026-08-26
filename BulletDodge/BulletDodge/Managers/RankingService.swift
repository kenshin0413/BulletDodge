import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class RankingService: ObservableObject {
    @Published private(set) var profile: RankingProfile?
    @Published private(set) var leaderboard: [LeaderboardEntry] = []
    @Published private(set) var isPreparing = false
    @Published private(set) var isLoadingLeaderboard = false
    @Published private(set) var submissionState: RankingSubmissionState = .idle
    @Published private(set) var previousRankForLatestSubmission: Int?
    @Published private(set) var lastError: String?
    @Published private(set) var selectedSeason = RankingSeason.current

    private let database = Firestore.firestore()
    private let isPreview: Bool

    init() {
#if DEBUG
        isPreview = ProcessInfo.processInfo.environment["BULLETDODGE_RANKING_PREVIEW"] == "1"
        if isPreview {
            let showsGuestState = ProcessInfo.processInfo.environment[
                "BULLETDODGE_RANKING_NO_PROFILE"
            ] == "1"
            let previewIcon: ProfileIcon = ProcessInfo.processInfo.environment[
                "BULLETDODGE_CHAMPION_ICON_PREVIEW"
            ] == "1" ? .seasonChampion : .curve
            if !showsGuestState {
                profile = RankingProfile(
                    uid: "preview-user",
                    displayName: "CurveMaster",
                    nameKey: "curvemaster",
                    icon: previewIcon,
                    unlockedIcons: previewIcon == .seasonChampion ? [.seasonChampion] : []
                )
            }
            leaderboard = [
                LeaderboardEntry(
                    id: OfficialRankingAccounts.developerUID,
                    displayName: "トゲ避け開発者",
                    icon: .developerRainbow,
                    survivalMilliseconds: 182_500,
                    dodgedCount: 421
                ),
                LeaderboardEntry(id: "two", displayName: "カーブ名人", icon: .orbit, survivalMilliseconds: 81_320, dodgedCount: 213),
                LeaderboardEntry(id: "preview-user", displayName: "CurveMaster", icon: previewIcon, survivalMilliseconds: 74_610, dodgedCount: 188),
                LeaderboardEntry(id: "four", displayName: "トゲよけ侍", icon: .shield, survivalMilliseconds: 68_050, dodgedCount: 171),
                LeaderboardEntry(id: "five", displayName: "Speed7", icon: .bolt, survivalMilliseconds: 59_470, dodgedCount: 149),
                LeaderboardEntry(id: "six", displayName: "NoHitRun", icon: .crown, survivalMilliseconds: 55_930, dodgedCount: 141),
                LeaderboardEntry(id: "seven", displayName: "六方向マスター", icon: .orbit, survivalMilliseconds: 52_280, dodgedCount: 132),
                LeaderboardEntry(id: "eight", displayName: "ArcRunner", icon: .curve, survivalMilliseconds: 48_640, dodgedCount: 124),
                LeaderboardEntry(id: "nine", displayName: "回避の達人", icon: .shield, survivalMilliseconds: 45_110, dodgedCount: 116),
                LeaderboardEntry(id: "ten", displayName: "SpikeStep", icon: .bolt, survivalMilliseconds: 41_870, dodgedCount: 108),
                LeaderboardEntry(id: "eleven", displayName: "DodgeFlow", icon: .crown, survivalMilliseconds: 38_550, dodgedCount: 101),
                LeaderboardEntry(id: "twelve", displayName: "カーブ読み", icon: .orbit, survivalMilliseconds: 35_120, dodgedCount: 94)
            ]
            if ProcessInfo.processInfo.environment[
                "BULLETDODGE_SHOW_RANKED_SHARE_PREVIEW"
            ] == "1" {
                submissionState = .submitted(isPersonalBest: true)
            }
        }
#else
        isPreview = false
#endif
    }

    var isSignedIn: Bool { Auth.auth().currentUser != nil }
    var currentSeason: RankingSeason { RankingSeason.current }
    var availableSeasons: [RankingSeason] { RankingSeason.available }
    var isViewingCurrentSeason: Bool { selectedSeason == currentSeason }

    func report(_ error: Error) {
        lastError = userMessage(for: error)
    }

    func prepare() async {
        guard !isPreview else { return }
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            if Auth.auth().currentUser == nil {
                _ = try await Auth.auth().signInAnonymously()
            }
            try await loadProfile()
        } catch {
            lastError = userMessage(for: error)
        }
    }

    func createProfile(displayName rawName: String, icon: ProfileIcon) async throws {
        try await ensureSignedIn()
        let displayName = RankingNameValidator.normalizedDisplayName(rawName)
        guard RankingNameValidator.isValid(displayName) else {
            throw RankingServiceError.invalidName
        }
        let key = RankingNameValidator.key(for: displayName)
        guard let uid = Auth.auth().currentUser?.uid else { throw RankingServiceError.authentication }

        let profileRef = database.collection("profiles").document(uid)
        let nameRef = database.collection("usernames").document(key)
        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    // Do not read the reservation first. Username documents are
                    // intentionally unreadable, and the create-only security rule
                    // atomically rejects an existing key without exposing it.
                    let now = FieldValue.serverTimestamp()
                    transaction.setData([
                        "ownerUid": uid,
                        "createdAt": now
                    ], forDocument: nameRef)
                    transaction.setData([
                        "uid": uid,
                        "displayName": displayName,
                        "nameKey": key,
                        "iconID": icon.rawValue,
                        "createdAt": now,
                        "updatedAt": now
                    ], forDocument: profileRef)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw RankingServiceError.nameAlreadyUsed
            }
            throw error
        }
        profile = RankingProfile(
            uid: uid,
            displayName: displayName,
            nameKey: key,
            icon: icon,
            unlockedIcons: []
        )
    }

    func updateProfile(displayName rawName: String, icon: ProfileIcon) async throws {
        guard let profile else { throw RankingServiceError.profileRequired }
        guard profile.availableIcons.contains(icon) else {
            throw RankingServiceError.iconNotUnlocked
        }
        let displayName = RankingNameValidator.normalizedDisplayName(rawName)
        guard RankingNameValidator.isValid(displayName) else {
            throw RankingServiceError.invalidName
        }

        let newKey = RankingNameValidator.key(for: displayName)
        let profileRef = database.collection("profiles").document(profile.uid)
        let oldNameRef = database.collection("usernames").document(profile.nameKey)
        let newNameRef = database.collection("usernames").document(newKey)
        let entryRef = leaderboardEntryReference(for: currentSeason, uid: profile.uid)

        do {
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    // Leaderboard entries are readable, so fetch it before any writes.
                    // Username reservations deliberately remain unreadable; the
                    // create-only rule rejects a duplicate without exposing it.
                    let entrySnapshot = try transaction.getDocument(entryRef)
                    let now = FieldValue.serverTimestamp()

                    if newKey != profile.nameKey {
                        transaction.setData([
                            "ownerUid": profile.uid,
                            "createdAt": now
                        ], forDocument: newNameRef)
                        transaction.deleteDocument(oldNameRef)
                    }

                    transaction.updateData([
                        "displayName": displayName,
                        "nameKey": newKey,
                        "iconID": icon.rawValue,
                        "updatedAt": now
                    ], forDocument: profileRef)

                    if entrySnapshot.exists {
                        transaction.updateData([
                            "displayName": displayName,
                            "iconID": icon.rawValue
                        ], forDocument: entryRef)
                    }
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw RankingServiceError.nameAlreadyUsed
            }
            throw error
        }

        self.profile = RankingProfile(
            uid: profile.uid,
            displayName: displayName,
            nameKey: newKey,
            icon: icon,
            unlockedIcons: profile.unlockedIcons
        )
        if isViewingCurrentSeason {
            leaderboard = leaderboard.map { entry in
                guard entry.id == profile.uid else { return entry }
                return LeaderboardEntry(
                    id: entry.id,
                    displayName: displayName,
                    icon: icon,
                    survivalMilliseconds: entry.survivalMilliseconds,
                    dodgedCount: entry.dodgedCount
                )
            }
        }
    }

    func beginRankedRun() async throws {
        try await ensureSignedIn()
        guard let profile else { throw RankingServiceError.profileRequired }
        submissionState = .idle
        let season = currentSeason
        try await database.collection("rankingRuns").document(profile.uid).setData([
            "uid": profile.uid,
            "ruleVersion": RankingRules.version,
            "seasonNumber": season.number,
            "seasonYear": season.year,
            "seasonMonth": season.month,
            "status": "active",
            "startedAt": FieldValue.serverTimestamp()
        ])
    }

    func submit(result: GameResult) async {
        guard let profile else {
            submissionState = .failed(L10n.text("ranking.error.profile_required"))
            return
        }
        submissionState = .submitting
        let score = max(0, Int((result.survivalTime * 1_000).rounded()))
        let season = currentSeason
        // Preserve the player's actual position before this score changes the
        // board. The result screen remains visible while this read completes.
        selectedSeason = season
        await loadLeaderboard(season: season)
        previousRankForLatestSubmission = leaderboard.firstIndex {
            $0.id == profile.uid
        }.map { $0 + 1 }
        let entryRef = leaderboardEntryReference(for: season, uid: profile.uid)
        let runRef = database.collection("rankingRuns").document(profile.uid)

        do {
            var isBest = false
            _ = try await database.runTransaction { transaction, errorPointer in
                do {
                    let run = try transaction.getDocument(runRef)
                    guard run.data()?["status"] as? String == "active" else {
                        throw RankingServiceError.missingRun
                    }
                    let oldScore = (try? transaction.getDocument(entryRef).data()?["survivalMilliseconds"] as? Int) ?? -1
                    isBest = score > oldScore
                    if isBest {
                        transaction.setData([
                            "uid": profile.uid,
                            "displayName": profile.displayName,
                            "iconID": profile.icon.rawValue,
                            "survivalMilliseconds": score,
                            "dodgedCount": result.dodgedCount,
                            "ruleVersion": RankingRules.version,
                            "seasonNumber": season.number,
                            "seasonYear": season.year,
                            "seasonMonth": season.month,
                            "achievedAt": FieldValue.serverTimestamp()
                        ], forDocument: entryRef)
                    }
                    transaction.updateData([
                        "status": "finished",
                        "finishedAt": FieldValue.serverTimestamp(),
                        "survivalMilliseconds": score
                    ], forDocument: runRef)
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            submissionState = .submitted(isPersonalBest: isBest)
            selectedSeason = season
            await loadLeaderboard(season: season)
        } catch {
            submissionState = .failed(userMessage(for: error))
        }
    }

    func selectSeason(_ season: RankingSeason) async {
        guard availableSeasons.contains(season) else { return }
        selectedSeason = season
        leaderboard = []
        await loadLeaderboard(season: season)
    }

    func loadLeaderboard(season: RankingSeason? = nil) async {
        guard !isPreview else { return }
        let season = season ?? selectedSeason
        isLoadingLeaderboard = true
        defer { isLoadingLeaderboard = false }
        do {
            let snapshot = try await database.collection("leaderboards")
                .document(season.id).collection("entries")
                .order(by: "survivalMilliseconds", descending: true)
                .order(by: "dodgedCount", descending: true)
                .limit(to: 100)
                .getDocuments()
            let entries: [LeaderboardEntry] = snapshot.documents.compactMap { document -> LeaderboardEntry? in
                let data = document.data()
                guard let name = data["displayName"] as? String,
                      let milliseconds = data["survivalMilliseconds"] as? Int,
                      let dodged = data["dodgedCount"] as? Int else { return nil }
                return LeaderboardEntry(
                    id: document.documentID,
                    displayName: name,
                    icon: ProfileIcon(rawValue: data["iconID"] as? String ?? "") ?? .shield,
                    survivalMilliseconds: milliseconds,
                    dodgedCount: dodged
                )
            }
            guard selectedSeason == season else { return }
            leaderboard = entries
        } catch {
            lastError = userMessage(for: error)
        }
    }

    func clearError() { lastError = nil }

    private func loadProfile() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let snapshot = try await database.collection("profiles").document(uid).getDocument()
        guard let data = snapshot.data(),
              let displayName = data["displayName"] as? String,
              let nameKey = data["nameKey"] as? String else {
            profile = nil
            return
        }
        let rewardSnapshot = try await database.collection("profileRewards")
            .document(uid)
            .getDocument()
        let unlockedIcons = Set(
            (rewardSnapshot.data()?["unlockedIconIDs"] as? [String] ?? [])
                .compactMap(ProfileIcon.init(rawValue:))
        )
        profile = RankingProfile(
            uid: uid,
            displayName: displayName,
            nameKey: nameKey,
            icon: ProfileIcon(rawValue: data["iconID"] as? String ?? "") ?? .shield,
            unlockedIcons: unlockedIcons
        )
    }

    private func ensureSignedIn() async throws {
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
    }

    private func leaderboardEntryReference(for season: RankingSeason, uid: String) -> DocumentReference {
        database.collection("leaderboards")
            .document(season.id)
            .collection("entries")
            .document(uid)
    }

    private func userMessage(for error: Error) -> String {
        if let known = error as? RankingServiceError { return known.localizedDescription }
        return L10n.text("ranking.error.network")
    }
}

private enum RankingServiceError: LocalizedError {
    case invalidName, nameAlreadyUsed, authentication, profileRequired, missingRun, iconNotUnlocked

    var errorDescription: String? {
        switch self {
        case .invalidName: L10n.text("ranking.error.invalid_name")
        case .nameAlreadyUsed: L10n.text("ranking.error.name_used")
        case .authentication: L10n.text("ranking.error.authentication")
        case .profileRequired: L10n.text("ranking.error.profile_required")
        case .missingRun: L10n.text("ranking.error.missing_run")
        case .iconNotUnlocked: L10n.text("ranking.error.icon_not_unlocked")
        }
    }
}
