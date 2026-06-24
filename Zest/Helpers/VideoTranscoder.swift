import Foundation
import AVFoundation

final class VideoTranscoder {
    static let shared = VideoTranscoder()
    
    private init() {}
    
    func needsConversion(url: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: url)
        Task {
            do {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                for track in videoTracks {
                    let formatDescriptions = try await track.load(.formatDescriptions)
                    for desc in formatDescriptions {
                        let mediaSubType = CMFormatDescriptionGetMediaSubType(desc)
                        if mediaSubType == 0x61763031 {
                            completion(true)
                            return
                        }
                    }
                }
                completion(false)
            } catch {
                completion(true)
            }
        }
    }
    
    private func findFFmpegPath() -> String? {

        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            return bundledPath
        }
        return nil
    }

    func transcode(url: URL, progressHandler: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        if let ffmpegPath = findFFmpegPath() {
            transcodeWithFFmpeg(ffmpegPath: ffmpegPath, url: url, progressHandler: progressHandler, completion: completion)
        } else {

            needsConversion(url: url) { needsConv in
                if needsConv {
                    DispatchQueue.main.async {
                        completion(nil, NSError(domain: "VideoTranscoder", code: -4, userInfo: [
                            NSLocalizedDescriptionKey: "This video uses the AV1 codec, which is not supported by your Mac's hardware. To play this video, please convert it to H.264 / HEVC, or install ffmpeg on your Mac (e.g. 'brew install ffmpeg') to enable automatic conversion."
                        ]))
                    }
                } else {
                    self.transcodeWithExportSession(url: url, progressHandler: progressHandler, completion: completion)
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
            
            var parsedDuration = duration
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let outputString = String(data: data, encoding: .utf8) {

                    if parsedDuration <= 0, let durRange = outputString.range(of: "Duration: \\d{2}:\\d{2}:\\d{2}\\.\\d{2}", options: .regularExpression) {
                        let durStr = String(outputString[durRange].dropFirst(10))
                        let components = durStr.split(separator: ":")
                        if components.count == 3 {
                            let hours = Double(components[0]) ?? 0
                            let minutes = Double(components[1]) ?? 0
                            let seconds = Double(components[2]) ?? 0
                            parsedDuration = hours * 3600 + minutes * 60 + seconds
                        }
                    }
                    

                    if parsedDuration > 0, let range = outputString.range(of: "time=\\d{2}:\\d{2}:\\d{2}\\.\\d{2}", options: .regularExpression) {
                        let timeStr = String(outputString[range].dropFirst(5))
                        let components = timeStr.split(separator: ":")
                        if components.count == 3 {
                            let hours = Double(components[0]) ?? 0
                            let minutes = Double(components[1]) ?? 0
                            let seconds = Double(components[2]) ?? 0
                            let elapsed = hours * 3600 + minutes * 60 + seconds
                            let progress = min(0.99, elapsed / parsedDuration)
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
