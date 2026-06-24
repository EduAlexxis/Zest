import SwiftUI
import AVFoundation
import AppKit
import IOKit.ps

struct VideoPlayerView: NSViewRepresentable {
    let url: URL
    var isLooping: Bool
    var playAudio: Bool
    var transform: VideoTransform

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: PlayerContainerView) {
        if view.player == nil || view.currentURL != url {
            view.cleanUpPlayer()
            
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .none
            player.automaticallyWaitsToMinimizeStalling = false
            view.playerLayer.player = player
            view.player = player
            view.currentURL = url
            view.setupEndObserver()
            view.attachStatusObserver()
        }
        

        view.playAudio = playAudio
        

        view.isLooping = isLooping


        view.apply(transform: transform)


        view.updateVolume()


        if let player = view.player {
            let shouldPause = (SettingsManager.shared.pauseInFullscreen && view.isAnyAppFullscreen()) ||
                              (SettingsManager.shared.pauseOnBattery && view.isCurrentlyOnBattery()) ||
                              (SettingsManager.shared.pauseOnLowPowerMode && view.isLowPowerMode()) ||
                              (SettingsManager.shared.pauseWhenFocused && view.isAnyAppFocusedOrSemiFullscreen())
            if shouldPause {
                player.pause()
            } else {
                player.play()
            }
        }
    }
}

final class PlayerContainerView: NSView {
    let playerLayer = AVPlayerLayer()
    var player: AVPlayer?
    var currentURL: URL?
    var isLooping: Bool = true
    var playAudio: Bool = false

    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    
    private var workspaceObserver: NSObjectProtocol?
    private var fullscreenTimer: Timer?
    private var lastShouldBeMuted: Bool?
    private var isAppCurrentlyActiveCached: Bool = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.contentsGravity = .resizeAspectFill
        playerLayer.isHidden = false
        layer?.addSublayer(playerLayer)
        playerLayer.needsDisplayOnBoundsChange = true
        

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppStateChange()
        }
        

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppStateChange()
        }
        
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkPeriodicStates()
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVolumeChanged),
            name: .wallpaperVolumeChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerStateChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePauseToggled),
            name: .wallpaperPauseToggled,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: .wallpaperSystemWake,
            object: nil
        )
        

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handlePowerStateChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppStateChange()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
        playerLayer.setNeedsDisplay()
    }

    func setupEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        guard let playerItem = player?.currentItem else { return }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            guard let self, self.isLooping, let player = self.player else { return }
            player.seek(to: .zero)
            player.play()
            

            self.currentVolumeLevel = 0.0
            self.updateVolume()
        }
        attachStatusObserver()
        setupTimeObserver()
    }

    func setupTimeObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, let duration = player.currentItem?.duration, duration.isNumeric else { return }
            
            let totalSeconds = CMTimeGetSeconds(duration)
            let currentSeconds = CMTimeGetSeconds(time)
            
            let fadeOutDuration = SettingsManager.shared.fadeOutDuration
            let remainingSeconds = totalSeconds - currentSeconds
            

            if remainingSeconds > 0 && remainingSeconds <= fadeOutDuration {
                let muteWhenInactive = SettingsManager.shared.muteWhenInactive
                let shouldBeMuted = (muteWhenInactive && !self.isAppCurrentlyActiveCached) || !self.playAudio
                
                if !shouldBeMuted {
                    let progress = remainingSeconds / fadeOutDuration
                    let baseVol = Float(SettingsManager.shared.volume)
                    let targetVol = baseVol * Float(progress)
                    

                    if self.fadeTimer == nil {
                        player.volume = targetVol
                    }
                } else {
                    if self.fadeTimer == nil {
                        player.volume = 0.0
                    }
                }
            }
        }
    }

    func attachStatusObserver() {
        statusObserver = player?.currentItem?.observe(\AVPlayerItem.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    let shouldPause = (SettingsManager.shared.pauseInFullscreen && self.isAnyAppFullscreen()) ||
                                      (SettingsManager.shared.pauseOnBattery && self.isCurrentlyOnBattery()) ||
                                      (SettingsManager.shared.pauseOnLowPowerMode && self.isLowPowerMode()) ||
                                      (SettingsManager.shared.pauseWhenFocused && self.isAnyAppFocusedOrSemiFullscreen())
                    if !shouldPause {
                        self.player?.play()
                    }
                    self.updateVolume()
                case .failed:
                    if let error = item.error {
                        print("AVPlayerItem failed: \(error.localizedDescription)")
                    } else {
                        print("AVPlayerItem failed with unknown error")
                    }
                case .unknown:
                    print("AVPlayerItem status unknown")
                @unknown default:
                    print("AVPlayerItem status unknown default")
                }
            }
        }
    }

    func apply(transform: VideoTransform) {
        var t = CATransform3DIdentity
        switch transform {
        case .none:
            t = CATransform3DIdentity
        case .mirror:
            t = CATransform3DScale(CATransform3DIdentity, -1, 1, 1)
        case .rotate90:
            t = CATransform3DRotate(CATransform3DIdentity, .pi/2, 0, 0, 1)
        case .rotate180:
            t = CATransform3DRotate(CATransform3DIdentity, .pi, 0, 0, 1)
        case .rotate270:
            t = CATransform3DRotate(CATransform3DIdentity, 3 * .pi/2, 0, 0, 1)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        playerLayer.setAffineTransform(.identity)
        playerLayer.transform = t
        CATransaction.commit()
    }
    

    func isAppActive(windowList: [[String: Any]]? = nil) -> Bool {

        guard let activeApp = NSWorkspace.shared.frontmostApplication else {
            isAppCurrentlyActiveCached = true
            return true
        }
        let activePid = activeApp.processIdentifier
        let zestPid = ProcessInfo.processInfo.processIdentifier
        
        let bid = activeApp.bundleIdentifier ?? ""
        if activePid == zestPid || bid == "com.apple.finder" || bid == "com.apple.dock" || bid == "com.apple.WindowManager" || bid.contains("Zest") {
            isAppCurrentlyActiveCached = true
            return true
        }
        


        let list: [[String: Any]]
        if let windowList {
            list = windowList
        } else {
            let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
            list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        }
        

        let hasNormalWindows = list.contains { window in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == activePid,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return false
            }
            return bounds.width > 100 && bounds.height > 100
        }
        
        let result = !hasNormalWindows
        isAppCurrentlyActiveCached = result
        return result
    }
    
    private func handleAppStateChange() {
        checkFullscreenState()
        updateVolume()
    }
    
    @objc private func handleVolumeChanged() {
        updateVolume()
    }
    
    @objc private func handlePowerStateChanged() {
        checkBatteryState()
    }
    
    @objc private func handlePauseToggled() {
        guard let player = player else { return }
        if WallpaperManager.shared.isPaused {
            player.pause()
        } else {

            checkFullscreenState()
        }
    }
    
    @objc private func handleSystemWake() {
        guard let player = player else { return }

        if WallpaperManager.shared.isPaused == false {
            let shouldPause = (SettingsManager.shared.pauseInFullscreen && isAnyAppFullscreen()) ||
                              (SettingsManager.shared.pauseOnBattery && isCurrentlyOnBattery()) ||
                              (SettingsManager.shared.pauseOnLowPowerMode && isLowPowerMode()) ||
                              (SettingsManager.shared.pauseWhenFocused && isAnyAppFocusedOrSemiFullscreen())
            if !shouldPause {
                player.play()
            }
        }
    }
    
    private var fadeTimer: Timer?
    private var currentFadeTarget: Float = 1.0
    private var currentFadeStep: Float = 0.0
    private var currentVolumeLevel: Float = 1.0

    func updateVolume() {
        guard let player = player else { return }
        let muteWhenInactive = SettingsManager.shared.muteWhenInactive
        let shouldBeMuted = (muteWhenInactive && !isAppActive()) || !playAudio
        lastShouldBeMuted = shouldBeMuted
        
        let targetVol: Float = shouldBeMuted ? 0.0 : Float(SettingsManager.shared.volume)
        

        fadeTimer?.invalidate()
        fadeTimer = nil
        
        let duration = shouldBeMuted ? SettingsManager.shared.fadeOutDuration : SettingsManager.shared.fadeInDuration
        if duration <= 0.01 {

            player.isMuted = shouldBeMuted
            player.volume = targetVol
            currentVolumeLevel = targetVol
            return
        }
        

        player.isMuted = false
        currentFadeTarget = targetVol
        
        let steps = 30
        let interval = duration / Double(steps)
        let delta = (targetVol - currentVolumeLevel) / Float(steps)
        
        var stepCount = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self, let player = self.player else {
                timer.invalidate()
                return
            }
            stepCount += 1
            self.currentVolumeLevel += delta
            

            if targetVol > 0 {
                self.currentVolumeLevel = min(self.currentVolumeLevel, targetVol)
            } else {
                self.currentVolumeLevel = max(self.currentVolumeLevel, 0.0)
            }
            player.volume = self.currentVolumeLevel
            
            if stepCount >= steps || self.currentVolumeLevel == targetVol {
                player.volume = targetVol
                if targetVol == 0 {
                    player.isMuted = true
                }
                timer.invalidate()
                self.fadeTimer = nil
            }
        }
    }
    
    func isAnyAppFocusedOrSemiFullscreen(windowList: [[String: Any]]? = nil) -> Bool {

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              frontApp.bundleIdentifier != "com.apple.finder",
              frontApp.bundleIdentifier != "com.apple.dock",
              frontApp.bundleIdentifier != "com.apple.WindowManager",
              frontApp.activationPolicy == .regular else {
            return false
        }
        
        let list: [[String: Any]]
        if let windowList {
            list = windowList
        } else {
            let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
            list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        }
        
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        
        for window in list {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == frontApp.processIdentifier,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            

            if let layer = window[kCGWindowLayer as String] as? Int, layer == 0 {

                let windowName = window[kCGWindowName as String] as? String ?? ""
                

                if frontApp.bundleIdentifier == "com.EduAlexxis.Zestz" {
                    continue
                }
                

                if bounds.width >= visibleFrame.width * 0.95 && bounds.height >= visibleFrame.height * 0.95 {
                    return true
                }
            }
        }
        
        return false
    }

    private func checkFullscreenState(windowList: [[String: Any]]? = nil) {
        guard let player = player else { return }
        if WallpaperManager.shared.isPaused {
            if player.rate != 0 {
                player.pause()
            }
            return
        }
        let pauseInFullscreen = SettingsManager.shared.pauseInFullscreen
        let pauseOnBattery = SettingsManager.shared.pauseOnBattery
        let pauseOnLowPowerMode = SettingsManager.shared.pauseOnLowPowerMode
        let pauseWhenFocused = SettingsManager.shared.pauseWhenFocused
        
        let shouldPause = (pauseInFullscreen && isAnyAppFullscreen(windowList: windowList)) ||
                           (pauseOnBattery && isCurrentlyOnBattery()) ||
                           (pauseOnLowPowerMode && isLowPowerMode()) ||
                           (pauseWhenFocused && isAnyAppFocusedOrSemiFullscreen(windowList: windowList))
        if shouldPause {
            if player.rate != 0 {
                player.pause()
            }
        } else {
            if player.rate == 0 && player.currentItem?.status == .readyToPlay {
                player.play()
            }
        }
    }
    
    private func checkBatteryState() {
        checkFullscreenState()
    }
    
    private func checkPeriodicStates() {

        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        
        checkFullscreenState(windowList: windowList)
        checkBatteryState()
        
        let muteWhenInactive = SettingsManager.shared.muteWhenInactive
        let shouldBeMuted = (muteWhenInactive && !isAppActive(windowList: windowList)) || !playAudio
        if shouldBeMuted != lastShouldBeMuted {
            updateVolume()
        }
    }
    
    func isLowPowerMode() -> Bool {
        return ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    func isCurrentlyOnBattery() -> Bool {

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return false
        }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                if let powerSourceState = description[kIOPSPowerSourceStateKey] as? String {
                    if powerSourceState == kIOPSBatteryPowerValue {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    func isAnyAppFullscreen(windowList: [[String: Any]]? = nil) -> Bool {
        let list: [[String: Any]]
        if let windowList {
            list = windowList
        } else {
            let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
            list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        }
        let screenFrame = NSScreen.main?.frame ?? .zero
        for window in list {
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID != ProcessInfo.processInfo.processIdentifier else {
                continue
            }
            if bounds.width >= screenFrame.width && bounds.height >= screenFrame.height {
                if let layer = window[kCGWindowLayer as String] as? Int, layer >= 0 {
                    if let app = NSRunningApplication(processIdentifier: pid_t(ownerPID)),
                       app.activationPolicy == .regular {
                        return true
                    }
                }
            }
        }
        return false
    }

    func cleanUpPlayer() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
    }

    deinit {
        cleanUpPlayer()
        if let workspaceObserver { NotificationCenter.default.removeObserver(workspaceObserver) }
        fadeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        fullscreenTimer?.invalidate()
    }
}


