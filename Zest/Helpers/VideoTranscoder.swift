import Foundation
import AVFoundation

final class VideoTranscoder {
    static let shared = VideoTranscoder()

    private init() {}

    func hasFFmpeg() -> Bool {
        findFFmpegPath() != nil
    }

    func homebrewPath() -> String? {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    func installFFmpegViaHomebrew(outputHandler: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        guard let brewPath = homebrewPath() else {
            completion(false)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install", "ffmpeg"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { outputHandler(text) }
        }

        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0 && self.hasFFmpeg())
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            completion(false)
        }
    }

    func installHomebrew(outputHandler: @escaping (String) -> Void, completion: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | /bin/bash"]

        var environment = ProcessInfo.processInfo.environment
        environment["NONINTERACTIVE"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { outputHandler(text) }
        }

        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0 && self.homebrewPath() != nil)
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            completion(false)
        }
    }

    func needsConversion(url: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        Task {
            do {
                _ = try await generator.image(at: .zero)
                completion(false)
            } catch {
                completion(true)
            }
        }
    }

    private func findFFmpegPath() -> String? {
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path), isExecutable(path) {
                return path
            }
        }
        return nil
    }

    private func isExecutable(_ path: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func transcode(url: URL, progressHandler: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        if let ffmpegPath = findFFmpegPath() {
            transcodeWithFFmpeg(ffmpegPath: ffmpegPath, url: url, progressHandler: progressHandler, completion: completion)
        } else {

            transcodeWithExportSession(url: url, progressHandler: progressHandler) { transcodedURL, exportError in
                if let transcodedURL {
                    completion(transcodedURL, nil)
                } else {
                    let detail = exportError?.localizedDescription ?? "unknown error"
                    completion(nil, NSError(domain: "VideoTranscoder", code: -4, userInfo: [
                        NSLocalizedDescriptionKey: "This video couldn't be converted (\(detail)). It may use AV1 or another codec/encoding macOS can't decode — install ffmpeg (e.g. 'brew install ffmpeg') to enable automatic conversion, or convert it to standard H.264 first."
                    ]))
                }
            }
        }
    }

    private func transcodeWithFFmpeg(ffmpegPath: String, url: URL, progressHandler: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let zestDir = appSupportDir.appendingPathComponent("Zest", isDirectory: true)
        try? fileManager.createDirectory(at: zestDir, withIntermediateDirectories: true, attributes: nil)

        let outputURL = zestDir.appendingPathComponent(UUID().uuidString + ".mp4")

        Task {
            let asset = AVURLAsset(url: url)
            let rawDuration: CMTime
            do {
                rawDuration = try await asset.load(.duration)
            } catch {
                rawDuration = .zero
            }
            let duration = CMTimeGetSeconds(rawDuration)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)

            process.arguments = [
                "-y",
                "-i", url.path,
                "-c:v", "libx264",
                "-preset", "superfast",
                "-crf", "23",
                "-c:a", "aac",
                outputURL.path
            ]

            let pipe = Pipe()
            process.standardError = pipe

            final class DurationTracker: @unchecked Sendable {
                private let lock = NSLock()
                private var _value: Double
                init(_ value: Double) { self._value = value }
                var value: Double {
                    get { lock.lock(); defer { lock.unlock() }; return _value }
                    set { lock.lock(); defer { lock.unlock() }; _value = newValue }
                }
            }
            let parsedDuration = DurationTracker(duration)

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let outputString = String(data: data, encoding: .utf8) {

                    if parsedDuration.value <= 0, let durRange = outputString.range(of: "Duration: \\d{2}:\\d{2}:\\d{2}\\.\\d{2}", options: .regularExpression) {
                        let durStr = String(outputString[durRange].dropFirst(10))
                        let components = durStr.split(separator: ":")
                        if components.count == 3 {
                            let hours = Double(components[0]) ?? 0
                            let minutes = Double(components[1]) ?? 0
                            let seconds = Double(components[2]) ?? 0
                            parsedDuration.value = hours * 3600 + minutes * 60 + seconds
                        }
                    }

                    if parsedDuration.value > 0, let range = outputString.range(of: "time=\\d{2}:\\d{2}:\\d{2}\\.\\d{2}", options: .regularExpression) {
                        let timeStr = String(outputString[range].dropFirst(5))
                        let components = timeStr.split(separator: ":")
                        if components.count == 3 {
                            let hours = Double(components[0]) ?? 0
                            let minutes = Double(components[1]) ?? 0
                            let seconds = Double(components[2]) ?? 0
                            let elapsed = hours * 3600 + minutes * 60 + seconds
                            let progress = min(0.99, elapsed / parsedDuration.value)
                            DispatchQueue.main.async {
                                progressHandler(progress)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    if proc.terminationStatus == 0 {
                        progressHandler(1.0)
                        completion(outputURL, nil)
                    } else {
                        completion(nil, NSError(domain: "VideoTranscoder", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "ffmpeg conversion failed with exit code \(proc.terminationStatus)."]))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    completion(nil, error)
                }
            }
        }
    }

    private func transcodeWithExportSession(url: URL, progressHandler: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        let asset = AVURLAsset(url: url)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil, NSError(domain: "VideoTranscoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize export session."]))
            return
        }

        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let zestDir = appSupportDir.appendingPathComponent("Zest", isDirectory: true)

        try? fileManager.createDirectory(at: zestDir, withIntermediateDirectories: true, attributes: nil)

        let outputURL = zestDir.appendingPathComponent(UUID().uuidString + ".mp4")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            progressHandler(Double(exportSession.progress))
        }

        exportSession.exportAsynchronously {
            timer.invalidate()
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(outputURL, nil)
                case .failed:
                    completion(nil, exportSession.error)
                case .cancelled:
                    completion(nil, NSError(domain: "VideoTranscoder", code: -2, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled."]))
                default:
                    completion(nil, NSError(domain: "VideoTranscoder", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown export status."]))
                }
            }
        }
    }
}
