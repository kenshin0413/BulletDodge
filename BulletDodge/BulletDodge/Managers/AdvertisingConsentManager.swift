import AppTrackingTransparency
import Combine
import GoogleMobileAds
import UserMessagingPlatform

/// Owns the privacy gate shared by every ad format in the app.
/// Future rewarded ads must also wait until `canRequestAds` becomes true.
@MainActor
final class AdvertisingConsentManager: ObservableObject {
    @Published private(set) var canRequestAds = false
    @Published private(set) var isPrivacyOptionsRequired = false
    @Published private(set) var consentRevision = 0

    private var isPreparing = false
    private var hasPrepared = false
    private var hasStartedMobileAds = false

    func prepareForAds() async {
        guard !isPreparing, !hasPrepared else { return }
        isPreparing = true
        defer { isPreparing = false }

        // Ask with the native iOS ATT alert directly. Doing this before UMP
        // prevents AdMob's optional generic IDFA explainer from appearing,
        // while UMP can still handle region-specific consent afterward.
        await requestTrackingAuthorizationIfNeeded()
        await updateConsentInformation()
        await presentRequiredConsentForm()

        hasPrepared = true
        refreshAdAvailability()
    }

    func presentPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            consentRevision += 1
        } catch {
#if DEBUG
            print("Privacy options form failed: \(error.localizedDescription)")
#endif
        }

        refreshAdAvailability()
    }

    private func updateConsentInformation() async {
        let parameters = RequestParameters()

        await withCheckedContinuation { continuation in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
#if DEBUG
                if let error {
                    print("Consent information update failed: \(error.localizedDescription)")
                }
#endif
                continuation.resume()
            }
        }

        refreshPrivacyOptionsRequirement()
    }

    private func presentRequiredConsentForm() async {
        do {
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
#if DEBUG
            print("Consent form failed: \(error.localizedDescription)")
#endif
        }

        refreshPrivacyOptionsRequirement()
    }

    private func requestTrackingAuthorizationIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }

        // Let the home screen settle before presenting the one-time system alert.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { _ in
                continuation.resume()
            }
        }
    }

    private func refreshPrivacyOptionsRequirement() {
        isPrivacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    private func refreshAdAvailability() {
        refreshPrivacyOptionsRequirement()
        canRequestAds = ConsentInformation.shared.canRequestAds

        guard canRequestAds, !hasStartedMobileAds else { return }
        hasStartedMobileAds = true
        MobileAds.shared.start()
    }
}
