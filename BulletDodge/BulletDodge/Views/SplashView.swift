import AVFoundation
import SwiftUI
import UIKit

struct SplashView: View {
    let onFinished: () -> Void

    @State private var player: AVPlayer?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var posterImage: UIImage?
    @State private var playbackTask: Task<Void, Never>?
    @State private var finishTask: Task<Void, Never>?
    @State private var didFinish = false
    @State private var didAttachPlayer = false
    @State private var isFadingOut = false

    private static let fadeOutDuration = 0.42

    private var splashResourceName: String {
        Bundle.main.preferredLocalizations.first == "ja" ? "splash-ja" : "splash-en"
    }

    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.008, blue: 0.012)

            if let posterImage {
                Image(uiImage: posterImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }

            if let player {
                SplashPlayerSurface(player: player, onAttached: playerDidAttach)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .background(Color(red: 0.008, green: 0.008, blue: 0.012))
        // Fade the player and poster as one composited surface. Removing the
        // AVPlayerLayer during a parent transition can otherwise drop frames.
        .compositingGroup()
        .opacity(isFadingOut ? 0 : 1)
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
            finishTask?.cancel()
            player?.pause()
            audioPlayer?.stop()
            deactivateAudioSession()
        }
    }

    private func startPlayback() {
        guard player == nil, !didFinish else { return }
        posterImage = loadPosterImage()
        configureAudioSession()
        audioPlayer = makeAudioPlayer()

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
        splashPlayer.automaticallyWaitsToMinimizeStalling = false
        // Physical devices can suppress an MP4's audio during launch. The
        // dedicated AVAudioPlayer below owns sound playback instead.
        splashPlayer.isMuted = true
        player = splashPlayer
    }

    private func playerDidAttach() {
        guard !didAttachPlayer, !didFinish, let player else { return }
        didAttachPlayer = true

#if DEBUG
        if ProcessInfo.processInfo.environment["BULLETDODGE_HOLD_SPLASH"] == "1" {
            player.seek(to: CMTime(seconds: 1.55, preferredTimescale: 600))
            return
        }
#endif

        // AVPlayerLayer can attach later on a physical device than in the
        // simulator. Starting here guarantees the first frame has a surface.
        audioPlayer?.currentTime = 0
        let didStartAudio = audioPlayer?.play() ?? false
#if DEBUG
        logAudioStart(didStartAudio, mode: "video")
#endif
        player.play()

        playbackTask = Task { @MainActor in
            // A corrupt or interrupted asset must never trap the user on launch.
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            finishOnce()
        }
    }

    private func loadPosterImage() -> UIImage? {
        let name = "\(splashResourceName)-poster"
        let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Splash"
        ) ?? Bundle.main.url(forResource: name, withExtension: "png")

        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func makeAudioPlayer() -> AVAudioPlayer? {
        let url = Bundle.main.url(
            forResource: "splash-sfx",
            withExtension: "m4a",
            subdirectory: "Splash"
        ) ?? Bundle.main.url(forResource: "splash-sfx", withExtension: "m4a")

        guard let url else { return nil }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.volume = 0.85
            audioPlayer.numberOfLoops = 0
            audioPlayer.prepareToPlay()
            return audioPlayer
        } catch {
            assertionFailure("Failed to prepare splash audio: \(error)")
            return nil
        }
    }

#if DEBUG
    private func logAudioStart(_ didStart: Bool, mode: String) {
        let route = AVAudioSession.sharedInstance().currentRoute.outputs
            .map(\.portType.rawValue)
            .joined(separator: ",")
        print("[Splash] audioStarted=\(didStart) mode=\(mode) route=\(route)")
    }
#endif

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        playbackTask?.cancel()

        // The home screen is already rendered underneath. First dissolve the
        // splash, then remove it after the animation has fully completed.
        // Player/audio cleanup remains in onDisappear to keep work off the fade.
        withAnimation(.easeInOut(duration: Self.fadeOutDuration)) {
            isFadingOut = true
        }

        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.fadeOutDuration))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        // Splash feedback should remain audible on a physical device even when
        // the Ring/Silent switch is enabled, while still respecting system volume.
        try? audioSession.setCategory(.playback, mode: .default, options: [])
        try? audioSession.setPreferredSampleRate(48_000)
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
    let onAttached: () -> Void

    func makeUIView(context: Context) -> SplashPlayerView {
        let view = SplashPlayerView()
        view.onAttached = onAttached
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: SplashPlayerView, context: Context) {
        uiView.onAttached = onAttached
        uiView.playerLayer.player = player
        uiView.notifyIfAttached()
    }
}

private final class SplashPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var onAttached: (() -> Void)?
    private var didNotifyAttachment = false

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

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifyIfAttached()
    }

    func notifyIfAttached() {
        guard window != nil, !didNotifyAttachment else { return }
        didNotifyAttachment = true
        DispatchQueue.main.async { [weak self] in
            self?.onAttached?()
        }
    }
}

#Preview(traits: .landscapeRight) {
    SplashView(onFinished: {})
}
