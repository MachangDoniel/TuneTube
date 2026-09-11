import CoreImage
import SwiftUI
import UIKit

/// Derives a background tint from album art, like YouTube Music's player,
/// which washes the screen in the cover's dominant colour.
@MainActor
enum ArtworkPalette {
    private static var cache: [URL: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func cachedColor(for url: URL?) -> Color? {
        url.flatMap { cache[$0] }
    }

    static func color(for url: URL?) async -> Color? {
        guard let url else { return nil }
        if let hit = cache[url] { return hit }
        guard let image = await ImageLoader.shared.image(for: url),
              let rgb = await averageRGB(of: image) else { return nil }
        let color = tint(from: rgb)
        cache[url] = color
        return color
    }

    /// CIAreaAverage over the whole image, done off the main actor.
    private static func averageRGB(of image: UIImage) async -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgImage = image.cgImage else { return nil }
        let context = self.context
        return await Task.detached(priority: .utility) {
            let input = CIImage(cgImage: cgImage)
            var extent = input.extent
            // 4:3 YouTube thumbnails are letterboxed; don't average the black bars in.
            if abs(extent.width / max(extent.height, 1) - 4.0 / 3.0) < 0.02 {
                extent = extent.insetBy(dx: 0, dy: extent.height * 0.125)
            }
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: extent),
            ]), let output = filter.outputImage else { return nil }

            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(output, toBitmap: &pixel, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)
            return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
        }.value
    }

    /// Keep the hue, but clamp brightness so white text always reads on top.
    private static func tint(from rgb: (r: CGFloat, g: CGFloat, b: CGFloat)) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return Color(hue: hue,
                     saturation: min(saturation * 1.1, 0.75),
                     brightness: min(max(brightness * 0.6, 0.16), 0.36))
    }
}
