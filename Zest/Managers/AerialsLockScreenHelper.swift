import Foundation
import AppKit
import AVFoundation

class AerialsLockScreenHelper {
    static let shared = AerialsLockScreenHelper()

    let zestUUID = "427FE53B-6C61-4659-984C-95DD578BA516"

    private init() {}

    func apply(videoURL: URL, completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            let aerialsDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
            let videosDir = aerialsDir.appendingPathComponent("videos")

            guard fm.fileExists(atPath: videosDir.path) else {
                DispatchQueue.main.async {
                    completion(false, "Aerials folder not found. Please open System Settings -> Wallpaper and download at least one Aerial wallpaper first.")
                }
                return
            }

            let thumbnailsDir = aerialsDir.appendingPathComponent("thumbnails")

            do {
                let files = try fm.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil)
                let nativeVideoURLs = files.filter { url in
                    let ext = url.pathExtension.lowercased()
                    let name = url.deletingPathExtension().lastPathComponent
                    return ext == "mov" && name.count == 36 && name != self.zestUUID && !name.hasSuffix(".original")
                }

                if nativeVideoURLs.isEmpty {
                    DispatchQueue.main.async {
                        completion(false, "No downloaded Apple Aerial wallpapers found. Please download at least one Aerial wallpaper (like Tahoe Day or Sonoma Horizon) in System Settings first.")
                    }
                    return
                }

                var copySuccessCount = 0
                for nativeURL in nativeVideoURLs {
                    let uuid = nativeURL.deletingPathExtension().lastPathComponent
                    let backupURL = videosDir.appendingPathComponent("\(uuid).mov.original")

                    if !fm.fileExists(atPath: backupURL.path) {
                        try? fm.copyItem(at: nativeURL, to: backupURL)
                        print("Backed up native asset: \(uuid)")
                    }

                    let nativeThumbURL = thumbnailsDir.appendingPathComponent("\(uuid).png")
                    let backupThumbURL = thumbnailsDir.appendingPathComponent("\(uuid).png.original")
                    if fm.fileExists(atPath: nativeThumbURL.path) && !fm.fileExists(atPath: backupThumbURL.path) {
                        try? fm.copyItem(at: nativeThumbURL, to: backupThumbURL)
                    }

                    let tempCopyURL = videosDir.appendingPathComponent("\(uuid)_tmp.mov")
                    let tempThumbURL = thumbnailsDir.appendingPathComponent("\(uuid)_tmp.png")
                    try? fm.removeItem(at: tempCopyURL)
                    try? fm.removeItem(at: tempThumbURL)

                    var copied = self.makeVideoOnlyCopy(source: videoURL, destination: tempCopyURL)
                    if !copied {

                        copied = (try? fm.copyItem(at: videoURL, to: tempCopyURL)) != nil
                    }
                    self.makeThumbnail(source: videoURL, destination: tempThumbURL)

                    if copied, fm.fileExists(atPath: tempCopyURL.path) {
                        if fm.fileExists(atPath: nativeURL.path) {
                            try? fm.removeItem(at: nativeURL)
                        }
                        try? fm.moveItem(at: tempCopyURL, to: nativeURL)

                        if fm.fileExists(atPath: tempThumbURL.path) {
                            if fm.fileExists(atPath: nativeThumbURL.path) {
                                try? fm.removeItem(at: nativeThumbURL)
                            }
                            try? fm.moveItem(at: tempThumbURL, to: nativeThumbURL)
                        }

                        copySuccessCount += 1
                    } else {
                        print("Fast copy failed for \(uuid)")
                    }
                }

                if copySuccessCount > 0 {

                    self.restartExtension()
                    DispatchQueue.main.async {
                        completion(true, "Wallpaper applied instantly! Sleep/Wake bypass engaged.")
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(false, "Failed to apply custom wallpaper.")
                    }
                }

            } catch {
                DispatchQueue.main.async {
                    completion(false, "Failed to scan wallpapers folder: \(error.localizedDescription)")
                }
            }
        }
    }

    private func makeVideoOnlyCopy(source: URL, destination: URL) -> Bool {
        let asset = AVURLAsset(url: source)
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        Task {
            defer { semaphore.signal() }
            do {
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    print("Video-only copy failed: no video track in source")
                    return
                }
                let preferredTransform = try await videoTrack.load(.preferredTransform)
                let duration = try await asset.load(.duration)

                let composition = AVMutableComposition()
                guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    return
                }
                try compVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
                compVideoTrack.preferredTransform = preferredTransform

                guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                    return
                }
                export.outputURL = destination
                export.outputFileType = .mov

                await export.export()
                success = export.status == .completed
                if !success {
                    print("Video-only copy failed: \(export.error?.localizedDescription ?? "unknown export error")")
                }
            } catch {
                print("Video-only copy failed: \(error.localizedDescription)")
            }
        }

        semaphore.wait()
        return success
    }

    @discardableResult
    private func makeThumbnail(source: URL, destination: URL) -> Bool {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let pngData = rep.representation(using: .png, properties: [:]) else { return false }
            try pngData.write(to: destination)
            return true
        } catch {
            print("Thumbnail generation failed: \(error.localizedDescription)")
            return false
        }
    }

    func restoreOriginalWallpaper() -> (Bool, String) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let aerialsDir = home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
        let videosDir = aerialsDir.appendingPathComponent("videos")
        let thumbnailsDir = aerialsDir.appendingPathComponent("thumbnails")

        guard fm.fileExists(atPath: videosDir.path) else {
            return (false, "Videos folder not found.")
        }

        do {
            let files = try fm.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil)
            var restoredCount = 0

            for fileURL in files {
                let path = fileURL.path
                if path.hasSuffix(".mov.original") {
                    let targetPath = path.replacingOccurrences(of: ".mov.original", with: ".mov")
                    let targetURL = URL(fileURLWithPath: targetPath)

                    if fm.fileExists(atPath: targetURL.path) {
                        try? fm.removeItem(at: targetURL)
                    }
                    try fm.copyItem(at: fileURL, to: targetURL)
                    try fm.removeItem(at: fileURL)

                    let uuid = targetURL.deletingPathExtension().lastPathComponent
                    let thumbURL = thumbnailsDir.appendingPathComponent("\(uuid).png")
                    let backupThumbURL = thumbnailsDir.appendingPathComponent("\(uuid).png.original")
                    if fm.fileExists(atPath: backupThumbURL.path) {
                        if fm.fileExists(atPath: thumbURL.path) {
                            try? fm.removeItem(at: thumbURL)
                        }
                        try fm.copyItem(at: backupThumbURL, to: thumbURL)
                        try fm.removeItem(at: backupThumbURL)
                    }

                    restoredCount += 1
                }
            }

            if restoredCount > 0 {
                restartExtension()
                return (true, "Restored \(restoredCount) original Apple wallpaper(s).")
            } else {
                return (false, "No backups found to restore.")
            }
        } catch {
            return (false, "Failed to restore: \(error.localizedDescription)")
        }
    }

    private func restartExtension() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", "WallpaperAerialsExtension"]
        try? process.run()

        let process2 = Process()
        process2.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process2.arguments = ["-x", "WallpaperAgent"]
        try? process2.run()

        print("Restarted WallpaperAerialsExtension and WallpaperAgent")
    }
}
