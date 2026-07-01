import ScreenSaver
import AVFoundation
import AppKit

@objc(ZestScreenSaverView)
class ZestScreenSaverView: ScreenSaverView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: Any?
    private var isSetup = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func resolveVideoURL() -> URL? {

        let sharedDefaults = UserDefaults(suiteName: "com.EduAlexxis.Zest.shared")
        let storedPath = sharedDefaults?.string(forKey: "activeWallpaperPath")

        if let path = storedPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let containerPath = home
            .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver")
            .appendingPathComponent("Data/Library/Application Support/Zest/activeWallpaper.mp4")

        if FileManager.default.fileExists(atPath: containerPath.path) {
            return containerPath
        }

        NSLog("ZestScreenSaver: No video found at stored path (\(storedPath ?? "nil")) or container fallback.")
        return nil
    }

    private func setup() {
        guard !isSetup else { return }
        isSetup = true

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        guard let videoURL = resolveVideoURL() else {
            NSLog("ZestScreenSaver: No valid video URL — showing black screen.")
            return
        }

        NSLog("ZestScreenSaver: Loading video from: \(videoURL.path)")

        let asset = AVURLAsset(url: videoURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)

        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        player.isMuted = true

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)

        self.player = player
        self.playerLayer = playerLayer

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero, completionHandler: { _ in
                player?.play()
            })
        }

        item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let item = object as? AVPlayerItem {
            switch item.status {
            case .readyToPlay:
                NSLog("ZestScreenSaver: AVPlayerItem ready to play ✅")
            case .failed:
                NSLog("ZestScreenSaver: AVPlayerItem failed ❌ — \(item.error?.localizedDescription ?? "unknown error")")
            case .unknown:
                NSLog("ZestScreenSaver: AVPlayerItem status unknown (loading...)")
            @unknown default:
                break
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        playerLayer?.frame = bounds
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        playerLayer?.frame = bounds
    }

    override func startAnimation() {
        super.startAnimation()
        player?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    override func animateOneFrame() {

    }

    override var hasConfigureSheet: Bool { return false }
    override var configureSheet: NSWindow? { return nil }

    deinit {
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        player?.currentItem?.removeObserver(self, forKeyPath: "status")
        player?.pause()
    }
}
