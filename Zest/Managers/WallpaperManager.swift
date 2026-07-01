import SwiftUI
import AppKit
import AVFoundation

final class WallpaperManager {
    static let shared = WallpaperManager()

    private var windows: [NSWindow] = []
    private var hostings: [NSHostingView<AnyView>] = []
    private var securityAccessActive = false
    private var activeURL: URL?

    private var lastLoop: Bool = true
    private var lastPlayAudio: Bool = false
    private var lastTransform: VideoTransform = .none

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSyncLockScreenEnabled),
            name: .syncLockScreenEnabled,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTargetModeChanged),
            name: .wallpaperTargetModeChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalDisplayModeChanged),
            name: .externalDisplayModeChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleExternalDisplayModeChanged() {
        guard let url = activeURL else { return }
        apply(url: url, loop: lastLoop, playAudio: lastPlayAudio, transform: lastTransform)
    }

    @objc private func handleScreenParametersChanged() {
        guard let url = activeURL else { return }

        apply(url: url, loop: lastLoop, playAudio: lastPlayAudio, transform: lastTransform)
    }

    func apply(url: URL, loop: Bool, playAudio: Bool, transform: VideoTransform, completion: @escaping (String?) -> Void = { _ in }) {

        stop()

        self.activeURL = url
        self.lastLoop = loop
        self.lastPlayAudio = playAudio
        self.lastTransform = transform
        self.securityAccessActive = url.startAccessingSecurityScopedResource()

        if SettingsManager.shared.wallpaperTargetMode == "lockscreen" || SettingsManager.shared.wallpaperTargetMode == "both" {
            AerialsLockScreenHelper.shared.apply(videoURL: url) { success, message in
                print("Lock screen wallpaper: \(message)")
                completion(message)
            }
        } else {
            completion(nil)
        }

        if SettingsManager.shared.wallpaperTargetMode == "desktop" || SettingsManager.shared.wallpaperTargetMode == "both" {

            for w in windows {
                w.orderOut(nil)
            }
            windows.removeAll()
            hostings.removeAll()

            let primaryScreen = NSScreen.screens.first
            let externalMode = SettingsManager.shared.externalDisplayMode

            for screen in NSScreen.screens {
                let screenFrame = screen.frame
                let style: NSWindow.StyleMask = []
                let w = NSWindow(contentRect: screenFrame, styleMask: style, backing: .buffered, defer: false)
                w.isOpaque = false
                w.backgroundColor = .clear

                w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                w.ignoresMouseEvents = true
                w.setFrame(screenFrame, display: true)

                let view: AnyView
                if screen == primaryScreen || externalMode == "live" {

                    let shouldPlayAudio = playAudio && (screen == primaryScreen)
                    view = AnyView(VideoPlayerView(url: url, isLooping: loop, playAudio: shouldPlayAudio, transform: transform).ignoresSafeArea())
                } else {
                    view = AnyView(StaticWallpaperView(url: url, transform: transform).ignoresSafeArea())
                }

                let hosting = NSHostingView(rootView: view)
                w.contentView = hosting
                w.orderBack(nil)
                w.makeKeyAndOrderFront(nil)

                windows.append(w)
                hostings.append(hosting)
            }
        }
    }

    func stop() {
        if securityAccessActive {
            activeURL?.stopAccessingSecurityScopedResource()
            securityAccessActive = false
        }
        activeURL = nil
        hostings.removeAll()
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
        isPaused = false
    }

    private(set) var isPaused = false
    var isScreenLocked = false

    func togglePause() -> Bool {
        isPaused.toggle()
        NotificationCenter.default.post(name: .wallpaperPauseToggled, object: nil)
        return isPaused
    }

    func prepareForSleep() {

        guard activeURL != nil else { return }
        NotificationCenter.default.post(name: .wallpaperLockPause, object: nil)
    }

    func resumeOnWake() {
        guard activeURL != nil else { return }

        NotificationCenter.default.post(name: .wallpaperLockResume, object: nil)

        for window in windows {

            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.orderBack(nil)
        }

        NotificationCenter.default.post(name: .wallpaperSystemWake, object: nil)
    }

    @objc private func handleSyncLockScreenEnabled() {
        if let url = activeURL {
            syncLockScreenToWallpaper(videoURL: url)
        }
    }

    private func syncLockScreenToWallpaper(videoURL: URL) {
        let mode = SettingsManager.shared.wallpaperTargetMode
        guard mode == "lockscreen" || mode == "both" else { return }

        AerialsLockScreenHelper.shared.apply(videoURL: videoURL) { success, message in
            print("Lock screen wallpaper sync: \(message)")
        }
    }

    @objc private func handleTargetModeChanged() {
        guard let url = activeURL else { return }

        if SettingsManager.shared.wallpaperTargetMode == "lockscreen" {
            hostings.removeAll()
            for window in windows {
                window.orderOut(nil)
            }
            windows.removeAll()
        } else {
            apply(url: url, loop: lastLoop, playAudio: lastPlayAudio, transform: lastTransform)
        }
    }

    func forceColdStartLockScreen() {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = ["-9", "WallpaperAgent"]
            try? process.run()

            let process2 = Process()
            process2.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process2.arguments = ["-9", "WallpaperAerialsExtension"]
            try? process2.run()
        }
    }
}

extension Notification.Name {
    static let wallpaperPauseToggled = Notification.Name("wallpaperPauseToggled")
    static let wallpaperSystemWake = Notification.Name("wallpaperSystemWake")
    static let wallpaperLockPause = Notification.Name("wallpaperLockPause")
    static let wallpaperLockResume = Notification.Name("wallpaperLockResume")
}
