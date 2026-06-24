import SwiftUI
import AppKit

@main
struct ZestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var mainWindow: NSWindow?
    var windowDelegateProxy: WindowDelegateProxy?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVolumeChanged),
            name: .wallpaperVolumeChanged,
            object: nil
        )
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    
    @objc private func handleWake() {

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            WallpaperManager.shared.resumeOnWake()
        }
    }
    
    @objc private func handleSleep() {

        WallpaperManager.shared.prepareForSleep()
    }
    
    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else if let window = NSApp.windows.first(where: { $0.level == .normal }) {
            self.mainWindow = window
            setupWindowProxy(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.level == .normal {
            self.mainWindow = window
            setupWindowProxy(window)
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    private func setupWindowProxy(_ window: NSWindow) {
        if !(window.delegate is WindowDelegateProxy) {
            let proxy = WindowDelegateProxy(originalDelegate: window.delegate)
            self.windowDelegateProxy = proxy
            window.delegate = proxy
        }
    }
    
    private var customMenu: NSMenu?
    private var volumeSlider: NSSlider?
    private var volumeLabel: NSTextField?
 
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: "Zest")
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Zest", action: #selector(menuOpenZest), keyEquivalent: "o"))
        
        let pauseItem = NSMenuItem(title: "Pause Wallpaper", action: #selector(menuTogglePause), keyEquivalent: "p")
        menu.addItem(pauseItem)
        
        menu.addItem(NSMenuItem.separator())
        

        let volumeItem = NSMenuItem()
        let volumeView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        
        let iconView = NSImageView(frame: NSRect(x: 14, y: 5, width: 20, height: 20))
        iconView.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume")
        iconView.contentTintColor = .labelColor
        volumeView.addSubview(iconView)
        
        let slider = NSSlider(frame: NSRect(x: 38, y: 5, width: 125, height: 20))
        slider.minValue = 0.0
        slider.maxValue = 1.0
        slider.doubleValue = SettingsManager.shared.volume
        slider.target = self
        slider.action = #selector(handleVolumeSliderChange(_:))
        volumeView.addSubview(slider)
        self.volumeSlider = slider
        
        let label = NSTextField(labelWithString: "\(Int(SettingsManager.shared.volume * 100))%")
        label.frame = NSRect(x: 165, y: 6, width: 45, height: 18)
        label.alignment = .right
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        volumeView.addSubview(label)
        self.volumeLabel = label
        
        volumeItem.view = volumeView
        menu.addItem(volumeItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Zest", action: #selector(menuQuit), keyEquivalent: "q"))
        
        self.customMenu = menu
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.clickCount == 2 {
            showMainWindow()
        } else {
            if let menu = customMenu {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
            }
        }
    }
    
    @objc private func handleVolumeSliderChange(_ sender: NSSlider) {
        SettingsManager.shared.volume = sender.doubleValue
        volumeLabel?.stringValue = "\(Int(sender.doubleValue * 100))%"
    }
    
    @objc private func handleVolumeChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let vol = SettingsManager.shared.volume
            self.volumeSlider?.doubleValue = vol
            self.volumeLabel?.stringValue = "\(Int(vol * 100))%"
        }
    }
    
    @objc private func menuOpenZest() {
        showMainWindow()
    }
    
    @objc private func menuTogglePause() {
        let isPaused = WallpaperManager.shared.togglePause()
        if let item = customMenu?.items.first(where: { $0.action == #selector(menuTogglePause) }) {
            item.title = isPaused ? "Resume Wallpaper" : "Pause Wallpaper"
        }
    }
    
    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}

class WindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var originalDelegate: NSWindowDelegate?
    
    init(originalDelegate: NSWindowDelegate?) {
        self.originalDelegate = originalDelegate
        super.init()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
    
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? false
    }
    
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let original = originalDelegate, original.responds(to: aSelector) {
            return original
        }
        return super.forwardingTarget(for: aSelector)
    }
}
