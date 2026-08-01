import Foundation
import Combine

enum AppStoreConfiguration {
    static let appID = "6794903133"

    static var productURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appID)")!
    }

    static var lookupURL: URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: appID),
            URLQueryItem(
                name: "country",
                value: Locale.current.region?.identifier.lowercased() ?? "jp"
            )
        ]
        return components?.url
    }
}

struct AvailableAppUpdate: Identifiable {
    let version: String
    let storeURL: URL

    var id: String { version }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    @Published var availableUpdate: AvailableAppUpdate?

    private var hasChecked = false

    func checkForUpdate() async {
        guard !hasChecked else { return }
        hasChecked = true

#if DEBUG
        if ProcessInfo.processInfo.environment["BULLETDODGE_SHOW_UPDATE_ALERT"] == "1" {
            availableUpdate = AvailableAppUpdate(version: "9.9", storeURL: AppStoreConfiguration.productURL)
            return
        }
#endif

        guard
            let lookupURL = AppStoreConfiguration.lookupURL,
            let currentVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: lookupURL)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else { return }

            let lookup = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            guard
                let app = lookup.results.first,
                app.version.compare(currentVersion, options: .numeric) == .orderedDescending
            else { return }

            availableUpdate = AvailableAppUpdate(
                version: app.version,
                storeURL: app.trackViewUrl ?? AppStoreConfiguration.productURL
            )
        } catch {
            // Version checks should never interrupt launch when the network or store is unavailable.
        }
    }
}

@MainActor
final class ReviewPromptPolicy {
    private let defaults: UserDefaults
    private let completedRunsKey = "review.completedRuns"
    private let lastRequestedDateKey = "review.lastRequestedDate"
    private let requestCooldown: TimeInterval = 15 * 24 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func registerCompletion() -> Bool {
        let completedRuns = defaults.integer(forKey: completedRunsKey) + 1
        defaults.set(completedRuns, forKey: completedRunsKey)

#if DEBUG
        if ProcessInfo.processInfo.environment["BULLETDODGE_FORCE_REVIEW_ELIGIBLE"] == "1" {
            return true
        }
#endif

        guard completedRuns >= 5 else { return false }

        if let lastRequestedDate = defaults.object(forKey: lastRequestedDateKey) as? Date {
            return Date().timeIntervalSince(lastRequestedDate) >= requestCooldown
        }

        return true
    }

    func markRequested() {
        defaults.set(Date(), forKey: lastRequestedDateKey)
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let version: String
    let trackViewUrl: URL?
}
