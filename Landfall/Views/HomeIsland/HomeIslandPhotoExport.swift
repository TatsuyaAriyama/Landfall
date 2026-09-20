import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// SceneKitの透明な空を画面と同じ色で合成し、見えていた構図をそのままSDR PNGへ書き出す。
@MainActor
enum HomeIslandPhotoExport {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let imageContext = CIContext(options: [
        .workingColorSpace: colorSpace,
        .outputColorSpace: colorSpace,
        .cacheIntermediates: false,
    ])

    /// iOS 17 and earlier lack `CIToneMapHeadroom`. Normalize SceneKit's
    /// four-times working range, then preserve the same reference-white and
    /// highlight points with Core Image's supported spline filter.
    private static func fallbackToneMap(_ image: CIImage) -> CIImage {
        let normalize = CIFilter.colorMatrix()
        normalize.inputImage = image
        normalize.rVector = CIVector(x: 0.25, y: 0, z: 0, w: 0)
        normalize.gVector = CIVector(x: 0, y: 0.25, z: 0, w: 0)
        normalize.bVector = CIVector(x: 0, y: 0, z: 0.25, w: 0)
        normalize.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let curve = CIFilter.toneCurve()
        curve.inputImage = normalize.outputImage
        curve.point0 = CGPoint(x: 0, y: 0)
        curve.point1 = CGPoint(x: 0.25, y: 0.776)
        curve.point2 = CGPoint(x: 0.50, y: 0.900)
        curve.point3 = CGPoint(x: 0.75, y: 0.975)
        curve.point4 = CGPoint(x: 1, y: 1)
        return curve.outputImage ?? image
    }

    static func render(
        sceneImage: UIImage,
        capturedAt: Date,
        brightness: HomeIslandBrightness = .standard
    ) -> WrappedCardImage? {
        // SCNView.snapshot()はHDR値を持つ一方でHDR色空間として印付けされないため、
        // Core Imageの自動変換と重ねず、明示したheadroomから一度だけSDRへ圧縮する。
        guard let scene = CIImage(image: sceneImage), !scene.extent.isEmpty
        else { return nil }

        let toneMapped: CIImage
        if #available(iOS 18.0, *) {
            let filter = CIFilter.toneMapHeadroom()
            filter.inputImage = scene
            filter.sourceHeadroom = 4
            filter.targetHeadroom = 1
            toneMapped = filter.outputImage ?? scene
        } else {
            toneMapped = fallbackToneMap(scene)
        }

        // Rasterize with UIKit before compositing so the cloud field uses the
        // same image sampling at small export sizes as it does on screen.
        let skyFormat = UIGraphicsImageRendererFormat()
        skyFormat.scale = 1
        skyFormat.opaque = true
        skyFormat.preferredRange = .standard
        let skyImage = UIGraphicsImageRenderer(
            size: scene.extent.size, format: skyFormat
        ).image { _ in
            HomeIslandSky.image(for: brightness).draw(
                in: CGRect(origin: .zero, size: scene.extent.size)
            )
        }
        guard let sky = CIImage(image: skyImage)
        else { return nil }
        let background = sky.transformed(by: CGAffineTransform(
            translationX: scene.extent.minX, y: scene.extent.minY
        )).cropped(to: scene.extent)
        let photo = toneMapped.composited(over: background)
        guard let cgImage = imageContext.createCGImage(
            photo,
            from: photo.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ), let data = UIImage(cgImage: cgImage).pngData()
        else { return nil }
        return WrappedCardImage(data: data, fileName: fileName(for: capturedAt))
    }

    private static func fileName(for date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "KeelMira-Island-%04d-%02d-%02d-%02d%02d%02d.png",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}
