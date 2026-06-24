import SwiftUI
import AppKit

final class WallpaperManager {
    static let shared = WallpaperManager()

    private var window: NSWindow?
    private var hosting: NSHostingView<AnyView>?
    private var securityAccessActive = false
    private var activeURL: URL?
    
    private var lastLoop: Bool = true
    private var lastPlayAudio: Bool = false
    private var lastTransform: VideoTransform = .none

    private init() {}

    func apply(url: URL, loop: Bool, playAudio: Bool, transform: VideoTransform) {

        stop()

        self.activeURL = url
        self.lastLoop = loop
        self.lastPlayAudio = playAudio
        self.lastTransform = transform
        self.securityAccessActive = url.startAccessingSecurityScopedResource()


        if window == nil {
            let screenFrame = NSScreen.main?.frame ?? .zero
            let style: NSWindow.StyleMask = []
            let w = NSWindow(contentRect: screenFrame, styleMask: style, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.setFrame(screenFrame, display: true)
            self.window = w
        }

        let view = VideoPlayerView(url: url, isLooping: loop, playAudio: playAudio, transform: transform)
            .ignoresSafeArea()
        let hosting = NSHostingView(rootView: AnyView(view))
        self.hosting = hosting
        window?.contentView = hosting
        window?.orderBack(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func stop() {
        if securityAccessActive {
            activeURL?.stopAccessingSecurityScopedResource()
            securityAccessActive = false
        }
        activeURL = nil
        hosting = nil
        window?.orderOut(nil)
        window = nil
        isPaused = false
    }
    
    private(set) var isPaused = false
    
    func togglePause() -> Bool {
        isPaused.toggle()
        NotificationCenter.default.post(name: .wallpaperPauseToggled, object: nil)
        return isPaused
    }
    
    func prepareForSleep() {

        if let url = activeURL {
            let loop = lastLoop
            let audio = lastPlayAudio
            let trans = lastTransform
            
            stop()
            

            self.activeURL = url
            self.lastLoop = loop
            self.lastPlayAudio = audio
            self.lastTransform = trans
        }
    }
    
    func resumeOnWake() {
        guard let url = activeURL else { return }
        

        apply(url: url, loop: lastLoop, playAudio: lastPlayAudio, transform: lastTransform)
        
        guard let window = window else { return }

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.orderBack(nil)
        

        NotificationCenter.default.post(name: .wallpaperSystemWake, object: nil)
    }
}

extension Notification.Name {
    static let wallpaperPauseToggled = Notification.Name("wallpaperPauseToggled")
    static let wallpaperSystemWake = Notification.Name("wallpaperSystemWake")
}
