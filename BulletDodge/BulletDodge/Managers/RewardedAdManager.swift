import Combine
import Foundation
import GoogleMobileAds

enum RewardedAdOutcome {
    case earned
    case unavailable
    case dismissedWithoutReward
    case failedToPresent
}

@MainActor
final class RewardedAdManager: NSObject, ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPresenting = false

    private var rewardedAd: RewardedAd?
    private var completion: ((RewardedAdOutcome) -> Void)?
    private var earnedReward = false
    private var isAdRequestAllowed = false
    private var loadGeneration = 0

    func setAdRequestAllowed(_ isAllowed: Bool) {
        isAdRequestAllowed = isAllowed
        if isAllowed {
            preload()
        } else if !isPresenting {
            loadGeneration += 1
            rewardedAd = nil
            isReady = false
        }
    }

    func consentDidChange() {
        guard !isPresenting else { return }
        loadGeneration += 1
        rewardedAd = nil
        isReady = false
        preload()
    }

    func preload() {
        guard isAdRequestAllowed,
              rewardedAd == nil,
              !isLoading,
              !isPresenting else { return }

        isLoading = true
        let generation = loadGeneration

        Task {
            defer { isLoading = false }
            do {
                let ad = try await RewardedAd.load(
                    with: RewardedAdConfiguration.adUnitID,
                    request: Request()
                )
                guard isAdRequestAllowed, generation == loadGeneration else {
                    preload()
                    return
                }
                ad.fullScreenContentDelegate = self
                rewardedAd = ad
                isReady = true
#if DEBUG
                print("Rewarded preload succeeded")
#endif
            } catch {
                isReady = false
#if DEBUG
                print("Rewarded preload failed: \(error.localizedDescription)")
#endif
            }
        }
    }

    func present(completion: @escaping (RewardedAdOutcome) -> Void) {
        guard isAdRequestAllowed, !isPresenting, let rewardedAd else {
            preload()
            completion(.unavailable)
            return
        }

        isPresenting = true
        isReady = false
        earnedReward = false
        self.completion = completion

        rewardedAd.present(from: nil) { [weak self] in
            self?.earnedReward = true
        }
    }

    private func finish(_ outcome: RewardedAdOutcome) {
        guard isPresenting else { return }
        isPresenting = false
        rewardedAd = nil
        isReady = false
        let completion = completion
        self.completion = nil
        completion?(outcome)
        preload()
    }
}

extension RewardedAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish(earnedReward ? .earned : .dismissedWithoutReward)
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
#if DEBUG
        print("Rewarded presentation failed: \(error.localizedDescription)")
#endif
        finish(.failedToPresent)
    }
}

private enum RewardedAdConfiguration {
#if DEBUG
    static let adUnitID = "ca-app-pub-3940256099942544/1712485313"
#else
    static let adUnitID = "ca-app-pub-2277987033120510/5857647082"
#endif
}
