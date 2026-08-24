import Foundation
import Combine
import GoogleMobileAds

@MainActor
final class InterstitialAdManager: NSObject, ObservableObject {
    private var interstitialAd: InterstitialAd?
    private var completion: (() -> Void)?
    private var isLoading = false
    private var isPresenting = false
    private var isAdRequestAllowed = false
    private var loadGeneration = 0

    func setAdRequestAllowed(_ isAllowed: Bool) {
        isAdRequestAllowed = isAllowed
        if isAllowed {
            preload()
        } else if !isPresenting {
            loadGeneration += 1
            interstitialAd = nil
        }
    }

    func consentDidChange() {
        guard !isPresenting else { return }
        loadGeneration += 1
        interstitialAd = nil
        preload()
    }

    func preload() {
        guard isAdRequestAllowed,
              interstitialAd == nil,
              !isLoading,
              !isPresenting else { return }
        isLoading = true
        let generation = loadGeneration

        Task {
            defer { isLoading = false }
            do {
                let ad = try await InterstitialAd.load(
                    with: AdMobConfiguration.interstitialAdUnitID,
                    request: Request()
                )
                guard isAdRequestAllowed, generation == loadGeneration else {
                    isLoading = false
                    preload()
                    return
                }
                ad.fullScreenContentDelegate = self
                interstitialAd = ad
            } catch {
#if DEBUG
                print("Interstitial preload failed: \(error.localizedDescription)")
#endif
            }
        }
    }

    func presentIfAvailable(onFinish: @escaping () -> Void) {
        guard isAdRequestAllowed, !isPresenting, let interstitialAd else {
            preload()
            onFinish()
            return
        }

        isPresenting = true
        completion = onFinish
        interstitialAd.present(from: nil)
    }

    private func finishPresentation() {
        guard isPresenting else { return }
        isPresenting = false
        interstitialAd = nil

        let completion = completion
        self.completion = nil
        completion?()
        preload()
    }
}

extension InterstitialAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finishPresentation()
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
#if DEBUG
        print("Interstitial presentation failed: \(error.localizedDescription)")
#endif
        finishPresentation()
    }
}

private enum AdMobConfiguration {
#if DEBUG
    static let interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
#else
    static let interstitialAdUnitID = "ca-app-pub-2277987033120510/6056129657"
#endif
}
