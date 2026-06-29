import SwiftUI
import AVFoundation

/// Full-screen loading screen shown on cold launch. Plays the background-removed
/// `TGK_T2P.mov` (HEVC with alpha) once over the brand-dark launch background
/// (matching the OS launch screen), then calls `onFinished`. Falls back to
/// finishing immediately if the asset is missing, and after a safety cap if
/// playback never reports completion.
struct SplashView: View {
    let onFinished: () -> Void

    private static let maxDuration: TimeInterval = 8

    private var videoURL: URL? {
        Bundle.main.url(forResource: "TGK_T2P", withExtension: "mov")
    }

    var body: some View {
        ZStack {
            Color.tgkLaunchBackground
                .ignoresSafeArea()

            if let videoURL {
                TransparentVideoView(url: videoURL, onEnded: onFinished)
                    .frame(maxWidth: 320, maxHeight: 320)
            }
        }
        .task {
            guard videoURL != nil else {
                onFinished()
                return
            }
            try? await Task.sleep(for: .seconds(Self.maxDuration))
            onFinished()
        }
    }
}

// MARK: - Transparent AVPlayer host

/// Plays an HEVC-with-alpha video once, muted, aspect-fit, with a clear
/// background so its transparency composites over whatever is behind it.
private struct TransparentVideoView: UIViewRepresentable {
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

        isOpaque = false
        backgroundColor = .clear
        player.isMuted = true
        player.actionAtItemEnd = .pause

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.clear.cgColor
        // Preserve the video's alpha channel when compositing.
        playerLayer.pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
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
