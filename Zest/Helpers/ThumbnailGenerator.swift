import SwiftUI
import AVFoundation

final class ThumbnailManager {
    static let shared = ThumbnailManager()
    private var cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 100
    }

    func getThumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        let nsURL = url as NSURL
        if let cachedImage = cache.object(forKey: nsURL) {
            completion(cachedImage)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let accessed = url.startAccessingSecurityScopedResource()
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 200)

            let time = CMTime(seconds: 1.0, preferredTimescale: 60)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
                if let cgImage = cgImage, result == .succeeded {
                    let nsImage = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
                    self.cache.setObject(nsImage, forKey: nsURL)
                    DispatchQueue.main.async {
                        completion(nsImage)
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            }
        }
    }
}

struct VideoThumbnailView: View {
    let url: URL
    @State private var image: NSImage? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ZStack {
                    Color.black.opacity(0.1)
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                ZStack {
                    Color.black.opacity(0.1)
                    Image(systemName: "video.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: url) {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        isLoading = true
        ThumbnailManager.shared.getThumbnail(for: url) { img in
            self.image = img
            self.isLoading = false
        }
    }
}
