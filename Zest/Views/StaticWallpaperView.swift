import SwiftUI

struct StaticWallpaperView: View {
    let url: URL
    let transform: VideoTransform

    @State private var frameImage: NSImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = frameImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Color.black
                }
            }
            .rotationEffect(rotation(for: transform))
            .scaleEffect(x: scaleX(for: transform), y: 1)
        }
        .onAppear {
            VideoFrameExtractor.shared.extractFrame(from: url) { image in
                self.frameImage = image
            }
        }
    }

    private func rotation(for transform: VideoTransform) -> Angle {
        switch transform {
        case .none, .mirror: return .zero
        case .rotate90: return .degrees(90)
        case .rotate180: return .degrees(180)
        case .rotate270: return .degrees(270)
        }
    }

    private func scaleX(for transform: VideoTransform) -> CGFloat {
        return transform == .mirror ? -1 : 1
    }
}
