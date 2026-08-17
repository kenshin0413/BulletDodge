//
//  BulletDodgeApp.swift
//  BulletDodge
//
//  Created by miyamotokenshin on R 8/07/06.
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        FirebaseApp.app()?.isDataCollectionDefaultEnabled = true

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
    var body: some Scene {
        WindowGroup {
            FixedLandscapeCanvas {
                LaunchFlowView()
            }
        }
    }
}

private struct FixedLandscapeCanvas<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let shouldRotate = UIDevice.current.userInterfaceIdiom == .pad
                && geometry.size.height > geometry.size.width
            let canvasSize = shouldRotate
                ? CGSize(width: geometry.size.height, height: geometry.size.width)
                : geometry.size

            content
                .frame(width: canvasSize.width, height: canvasSize.height)
                .rotationEffect(.degrees(shouldRotate ? 90 : 0))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}

private struct LaunchFlowView: View {
    @State private var isShowingSplash = !DebugSplashOptions.shouldSkip

    var body: some View {
        ZStack {
            // Keep the home screen ready behind the splash so its own fade can
            // reveal a fully laid-out screen without a blank or loading frame.
            ContentView()
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
    }
}

private enum DebugSplashOptions {
    static let shouldSkip = ProcessInfo.processInfo.environment["BULLETDODGE_SKIP_SPLASH"] == "1"
    static let shouldHold = ProcessInfo.processInfo.environment["BULLETDODGE_HOLD_SPLASH"] == "1"
}
