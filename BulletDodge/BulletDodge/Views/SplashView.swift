import AVFoundation
import SwiftUI
import UIKit

struct SplashView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player: AVPlayer?
    @State private var playbackTask: Task<Void, Never>?
    @State private var didFinish = false

    private var splashResourceName: String {
        Bundle.main.preferredLocalizations.first == "ja" ? "splash-ja" : "splash-en"
    }

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.008, blue: 0.012)

            if let player {
                SplashPlayerSurface(player: player)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .background(Color(red: 0.008, green: 0.008, blue: 0.012))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("app.title"))
        .onAppear(perform: startPlayback)
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let endedItem = notification.object as? AVPlayerItem,
                  endedItem === player?.currentItem else { return }
            finishOnce()
        }
        .onDisappear {
            playbackTask?.cancel()
            player?.pause()
            deactivateAudioSession()
        }
    }

    private func startPlayback() {
        guard player == nil, !didFinish else { return }

        if reduceMotion {
            playbackTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                finishOnce()
            }
            return
        }

        guard let url = Bundle.main.url(
            forResource: splashResourceName,
            withExtension: "mp4",
            subdirectory: "Splash"
        ) ?? Bundle.main.url(forResource: splashResourceName, withExtension: "mp4") else {
            finishOnce()
            return
        }

        let item = AVPlayerItem(url: url)
        let splashPlayer = AVPlayer(playerItem: item)
        splashPlayer.actionAtItemEnd = .pause
        configureAudioSession()
        splashPlayer.isMuted = false
        player = splashPlayer

#if DEBUG
        if ProcessInfo.processInfo.environment["BULLETDODGE_HOLD_SPLASH"] == "1" {
            splashPlayer.seek(to: CMTime(seconds: 1.55, preferredTimescale: 600))
            return
        }
#endif

        splashPlayer.play()

        playbackTask = Task { @MainActor in
            // A corrupt or interrupted asset must never trap the user on launch.
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            finishOnce()
        }
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        playbackTask?.cancel()
        player?.pause()
        onFinished()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? audioSession.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
    }
}

private struct SplashPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> SplashPlayerView {
        let view = SplashPlayerView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: SplashPlayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class SplashPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("SplashPlayerView requires AVPlayerLayer")
        }
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.008, green: 0.008, blue: 0.012, alpha: 1)
        playerLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#Preview {
    SplashView(onFinished: {})
        .previewInterfaceOrientation(.landscapeRight)
}
