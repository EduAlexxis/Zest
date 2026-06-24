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

    private init() {
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
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
}

extension Notification.Name {
    static let wallpaperVolumeChanged = Notification.Name("wallpaperVolumeChanged")
}
