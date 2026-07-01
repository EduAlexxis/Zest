import Foundation
import SwiftUI
import ServiceManagement
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            toggleLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var wallpaperTargetMode: String {
        didSet {
            UserDefaults.standard.set(wallpaperTargetMode, forKey: "wallpaperTargetMode")
            handleTargetModeChange()
        }
    }

    @Published var externalDisplayMode: String {
        didSet {
            UserDefaults.standard.set(externalDisplayMode, forKey: "externalDisplayMode")
            NotificationCenter.default.post(name: .externalDisplayModeChanged, object: nil)
        }
    }

    @Published var pauseInFullscreen: Bool {
        didSet {
            UserDefaults.standard.set(pauseInFullscreen, forKey: "pauseInFullscreen")
        }
    }

    @Published var muteWhenInactive: Bool {
        didSet {
            UserDefaults.standard.set(muteWhenInactive, forKey: "muteWhenInactive")
        }
    }

    @Published var appTheme: String {
        didSet {
            UserDefaults.standard.set(appTheme, forKey: "appTheme")
            applyTheme()
        }
    }

    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "volume")
            NotificationCenter.default.post(name: .wallpaperVolumeChanged, object: nil)
        }
    }

    @Published var pauseOnBattery: Bool {
        didSet {
            UserDefaults.standard.set(pauseOnBattery, forKey: "pauseOnBattery")
        }
    }

    @Published var pauseOnLowPowerMode: Bool {
        didSet {
            UserDefaults.standard.set(pauseOnLowPowerMode, forKey: "pauseOnLowPowerMode")
        }
    }

    @Published var fadeInDuration: Double {
        didSet {
            UserDefaults.standard.set(fadeInDuration, forKey: "fadeInDuration")
        }
    }

    @Published var fadeOutDuration: Double {
        didSet {
            UserDefaults.standard.set(fadeOutDuration, forKey: "fadeOutDuration")
        }
    }

    @Published var hideDesktopElements: Bool {
        didSet {
            UserDefaults.standard.set(hideDesktopElements, forKey: "hideDesktopElements")
            updateDesktopElementsVisibility(hideDesktopElements)
        }
    }

    @Published var pauseWhenFocused: Bool {
        didSet {
            UserDefaults.standard.set(pauseWhenFocused, forKey: "pauseWhenFocused")
        }
    }

    @Published var screenSaverInstalled: Bool = false

    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.wallpaperTargetMode = UserDefaults.standard.string(forKey: "wallpaperTargetMode") ?? "both"
        self.externalDisplayMode = UserDefaults.standard.string(forKey: "externalDisplayMode") ?? "live"
        self.pauseInFullscreen = UserDefaults.standard.object(forKey: "pauseInFullscreen") as? Bool ?? true
        self.muteWhenInactive = UserDefaults.standard.object(forKey: "muteWhenInactive") as? Bool ?? true
        self.appTheme = UserDefaults.standard.string(forKey: "appTheme") ?? "System"
        self.volume = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1.0
        self.pauseOnBattery = UserDefaults.standard.bool(forKey: "pauseOnBattery")
        self.pauseOnLowPowerMode = UserDefaults.standard.bool(forKey: "pauseOnLowPowerMode")
        self.fadeInDuration = UserDefaults.standard.object(forKey: "fadeInDuration") as? Double ?? 1.0
        self.fadeOutDuration = UserDefaults.standard.object(forKey: "fadeOutDuration") as? Double ?? 1.0
        self.hideDesktopElements = UserDefaults.standard.bool(forKey: "hideDesktopElements")
        self.pauseWhenFocused = UserDefaults.standard.bool(forKey: "pauseWhenFocused")

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let binPath = homeDir
            .appendingPathComponent("Library/Screen Savers/Zest.saver")
            .appendingPathComponent("Contents/MacOS/Zest")
        self.screenSaverInstalled = FileManager.default.fileExists(atPath: binPath.path)
    }

    private func updateDesktopElementsVisibility(_ hide: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"]

        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killProcess.arguments = ["Finder"]

        do {
            try process.run()
            process.waitUntilExit()

            try killProcess.run()
        } catch {
            print("Failed to change desktop elements visibility: \(error)")
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login error: \(error.localizedDescription)")
        }
    }

    func applyTheme() {
        DispatchQueue.main.async {
            switch self.appTheme {
            case "Light":
                NSApp.appearance = NSAppearance(named: .aqua)
            case "Dark":
                NSApp.appearance = NSAppearance(named: .darkAqua)
            default:
                NSApp.appearance = nil
            }
        }
    }

    private func handleTargetModeChange() {
        if wallpaperTargetMode == "lockscreen" || wallpaperTargetMode == "both" {
            NotificationCenter.default.post(name: .syncLockScreenEnabled, object: nil)
            installScreenSaver()
        }
        NotificationCenter.default.post(name: .wallpaperTargetModeChanged, object: nil)
    }

    func reinstallScreenSaver() {
        installScreenSaver()
    }

    private func installScreenSaver() {
        guard let saverURL = Bundle.main.url(forResource: "Zest", withExtension: "saver") else {
            print("Zest.saver not found in app bundle")
            return
        }

        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let screenSaversDir = homeDir.appendingPathComponent("Library/Screen Savers", isDirectory: true)

        do {
            if !fileManager.fileExists(atPath: screenSaversDir.path) {
                try fileManager.createDirectory(at: screenSaversDir, withIntermediateDirectories: true)
            }

            let destURL = screenSaversDir.appendingPathComponent("Zest.saver")

            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }

            try fileManager.copyItem(at: saverURL, to: destURL)

            setZestAsActiveScreenSaver(saverPath: destURL.path)

            DispatchQueue.main.async {
                self.screenSaverInstalled = true
            }
        } catch {
            print("Failed to install screensaver bundle: \(error)")
        }
    }

    private func setZestAsActiveScreenSaver(saverPath: String) {

        let script = """
        defaults -currentHost write com.apple.screensaver moduleDict -dict \
            moduleName Zest \
            path "\(saverPath)" \
            type 0
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("Failed to set screen saver defaults: \(error)")
        }
    }

    func checkScreenSaverInstalled() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let saverPath = homeDir.appendingPathComponent("Library/Screen Savers/Zest.saver")
        let binPath = saverPath.appendingPathComponent("Contents/MacOS/Zest")
        screenSaverInstalled = FileManager.default.fileExists(atPath: binPath.path)
    }
}

extension Notification.Name {
    static let wallpaperVolumeChanged = Notification.Name("wallpaperVolumeChanged")
    static let syncLockScreenEnabled = Notification.Name("syncLockScreenEnabled")
    static let wallpaperTargetModeChanged = Notification.Name("wallpaperTargetModeChanged")
    static let externalDisplayModeChanged = Notification.Name("externalDisplayModeChanged")
}
