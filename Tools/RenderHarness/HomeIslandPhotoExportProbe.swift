import UIKit

// The export's transport value; the app adds its sharing conformance elsewhere.
struct WrappedCardImage {
    let data: Data
    let fileName: String
}

@main
@MainActor
enum HomeIslandPhotoExportProbe {
    static func main() {
        for size in [CGSize(width: 32, height: 64), CGSize(width: 64, height: 32)] {
            var previousTop = 0
            for brightness in HomeIslandBrightness.allCases {
                let blank = render(size: size) { _ in }
                let expected = render(size: size) { _ in
                    HomeIslandSky.image(for: brightness).draw(in: CGRect(origin: .zero, size: size))
                }
                guard let export = HomeIslandPhotoExport.render(
                    sceneImage: blank, capturedAt: Date(timeIntervalSince1970: 0),
                    brightness: brightness
                ), let actual = UIImage(data: export.data) else {
                    fatalError("Cannot export \(brightness)")
                }
                precondition(actual.size == size, "Export must preserve the composition dimensions")
                precondition(export.fileName.hasSuffix(".png"))
                let actualPixels = pixels(actual)
                let expectedPixels = pixels(expected)
                for index in stride(from: 0, to: actualPixels.count, by: 4) {
                    precondition(actualPixels[index + 3] == 255, "Sky must export opaque")
                    for channel in 0..<3 {
                        precondition(
                            abs(Int(actualPixels[index + channel]) - Int(expectedPixels[index + channel])) <= 3,
                            "Exported sky must match the displayed sky at every brightness level"
                        )
                    }
                }
                let top = Int(actualPixels[0])
                precondition(top > previousTop, "Saved brightness must survive export")
                previousTop = top

                let foreground = render(size: size) { renderer in
                    UIColor.black.setFill()
                    renderer.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
                }
                let composite = HomeIslandPhotoExport.render(
                    sceneImage: foreground, capturedAt: .now, brightness: brightness
                )!
                let compositePixels = pixels(UIImage(data: composite.data)!)
                precondition(compositePixels[0] > 20, "Transparent sky must reveal the gradient")
                let bottom = compositePixels.count - 4
                precondition(compositePixels[bottom] < 3, "Opaque scene content must cover the sky")
            }
        }
        print("PASS photo sky parity, all five brightness levels, portrait/landscape dimensions, opacity and foreground compositing")
    }

    private static func render(
        size: CGSize, drawing: (UIGraphicsImageRendererContext) -> Void
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image(actions: drawing)
    }

    private static func pixels(_ image: UIImage) -> [UInt8] {
        let cgImage = image.cgImage!
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return bytes
    }
}
