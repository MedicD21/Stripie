import SwiftUI
import AVFoundation

/// Full-screen video loading screen shown on cold launch. Plays `TGK_T2P.mp4`
/// once over the brand-dark background (matching the OS launch screen), then
/// calls `onFinished`. Falls back to finishing immediately if the asset is
/// missing, and after a safety timeout if playback never reports completion.
struct SplashVideoView: View {
    let onFinished: () -> Void

    private static let maxDuration: Duration = .seconds(8)

    var body: some View {
        ZStack {
            Color.tgkLaunchBackground
                .ignoresSafeArea()

            if let url = Bundle.main.url(forResource: "TGK_T2P", withExtension: "mp4") {
                VideoPlayerLayerView(url: url, onEnded: onFinished)
                    .ignoresSafeArea()
            }
        }
        .task {
            // Safety net: never trap the user on the splash if the video is
            // missing or never posts its end-of-playback notification.
            if Bundle.main.url(forResource: "TGK_T2P", withExtension: "mp4") == nil {
                onFinished()
                return
            }
            try? await Task.sleep(for: Self.maxDuration)
            onFinished()
        }
    }
}

// MARK: - AVPlayerLayer host

/// Plays a video once, muted, aspect-fit, with no transport controls.
private struct VideoPlayerLayerView: UIViewRepresentable {
    let url: URL
    let onEnded: () -> Void

    func makeUIView(context: Context) -> PlayerContainerView {
        PlayerContainerView(url: url, onEnded: onEnded)
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}
}

private final class PlayerContainerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private let player: AVPlayer
    private let onEnded: () -> Void
    private var didFinish = false

    init(url: URL, onEnded: @escaping () -> Void) {
        self.player = AVPlayer(url: url)
        self.onEnded = onEnded
        super.init(frame: .zero)

        backgroundColor = .clear
        player.isMuted = true
        player.actionAtItemEnd = .pause
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        player.play()
    }

    @objc private func playbackDidEnd() {
        guard !didFinish else { return }
        didFinish = true
        let finish = onEnded
        DispatchQueue.main.async { finish() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
