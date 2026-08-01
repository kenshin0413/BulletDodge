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
    return true
  }
}

@main
struct BulletDodgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            LaunchFlowView()
        }
    }
}

private struct LaunchFlowView: View {
    @State private var isShowingSplash = !DebugSplashOptions.shouldSkip

    var body: some View {
        ZStack {
            if !isShowingSplash {
                ContentView()
                    .transition(.opacity)
            }

            if isShowingSplash {
                SplashView {
                    guard !DebugSplashOptions.shouldHold else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        isShowingSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(Color(red: 0.008, green: 0.008, blue: 0.012))
    }
}

private enum DebugSplashOptions {
    static let shouldSkip = ProcessInfo.processInfo.environment["BULLETDODGE_SKIP_SPLASH"] == "1"
    static let shouldHold = ProcessInfo.processInfo.environment["BULLETDODGE_HOLD_SPLASH"] == "1"
}
