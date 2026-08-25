//
//  BulletDodgeApp.swift
//  BulletDodge
//
//  Created by miyamotokenshin on R 8/07/06.
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import FirebaseAppCheck

#if !DEBUG
private final class ProductionAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
#if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
#else
        AppCheck.setAppCheckProviderFactory(ProductionAppCheckProviderFactory())
#endif
        FirebaseApp.configure()

        FirebaseApp.app()?.isDataCollectionDefaultEnabled = true

#if DEBUG
        RuleBoundaryChecks.run()
#endif

        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .landscape
    }
}

@main
struct BulletDodgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            FixedLandscapeCanvas {
                LaunchFlowView()
            }
                .task {
                    // scenePhase does not necessarily change after the first frame,
                    // so request landscape explicitly during initial presentation too.
                    requestLandscapeGeometry()
                    try? await Task.sleep(for: .milliseconds(300))
                    requestLandscapeGeometry()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    requestLandscapeGeometry()
                }
        }
    }

    private func requestLandscapeGeometry() {
        // iPadOS 26 doesn't visually rotate a landscape-only scene while the
        // device is held in portrait. The iPad canvas handles that case itself.
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        let preferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: .landscape
        )
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(preferences) { error in
#if DEBUG
                print("Landscape geometry request failed: \(error.localizedDescription)")
#endif
            }
        }
    }

}

private struct LaunchFlowView: View {
    @StateObject private var advertisingConsentManager = AdvertisingConsentManager()
    @State private var isShowingSplash = !DebugSplashOptions.shouldSkip

    var body: some View {
        ZStack {
            // Keep the home screen ready behind the splash so its own fade can
            // reveal a fully laid-out screen without a blank or loading frame.
            ContentView(advertisingConsentManager: advertisingConsentManager)
                .allowsHitTesting(!isShowingSplash)

            if isShowingSplash {
                SplashView {
                    guard !DebugSplashOptions.shouldHold else { return }
                    isShowingSplash = false
                }
                .zIndex(1)
            }
        }
        .background(Color(red: 0.91, green: 0.85, blue: 0.73))
        .task(id: isShowingSplash) {
            guard !isShowingSplash else { return }
#if DEBUG
            guard ProcessInfo.processInfo.environment["BULLETDODGE_SKIP_ADS_SETUP"] != "1" else { return }
#endif
            await advertisingConsentManager.prepareForAds()
        }
    }
}

/// Keeps the game visually landscape on iPad even when iPadOS presents its
/// scene in portrait. iPhone continues to use the native landscape lock.
private struct FixedLandscapeCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let isPortraitIPad = UIDevice.current.userInterfaceIdiom == .pad
                && geometry.size.height > geometry.size.width

            content
                .frame(
                    width: isPortraitIPad ? geometry.size.height : geometry.size.width,
                    height: isPortraitIPad ? geometry.size.width : geometry.size.height
                )
                .rotationEffect(.degrees(isPortraitIPad ? 90 : 0))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
    }
}

private enum DebugSplashOptions {
    static let shouldSkip = ProcessInfo.processInfo.environment["BULLETDODGE_SKIP_SPLASH"] == "1"
    static let shouldHold = ProcessInfo.processInfo.environment["BULLETDODGE_HOLD_SPLASH"] == "1"
}
