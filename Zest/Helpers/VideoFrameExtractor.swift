import AVFoundation
import AppKit

class VideoFrameExtractor {
    static let shared = VideoFrameExtractor()

    private var cache = [URL: NSImage]()

    private init() {}

    func extractFrame(from url: URL, completion: @escaping (NSImage?) -> Void) {
        if let cached = cache[url] {
            completion(cached)
            return
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)

        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] requestedTime, image, actualTime, result, error in
            guard let cgImage = image, error == nil else {
                print("Error extracting frame: \(error?.localizedDescription ?? "unknown error")")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            DispatchQueue.main.async {
                self?.cache[url] = nsImage
                completion(nsImage)
            }
        }
    }
}
