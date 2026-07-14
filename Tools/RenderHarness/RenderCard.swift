import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// カードをPNGに書き出す(macOS用の確認ハーネス。アプリ本体には含めない)。
@MainActor
func renderCard(_ view: some View, name: String, outDir: String, scale: CGFloat = 3) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let cgImage = renderer.cgImage else {
        print("RENDER FAILED: \(name)")
        return
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        print("DESTINATION FAILED: \(url.path)")
        return
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    if CGImageDestinationFinalize(dest) {
        print("WROTE \(url.path)")
    } else {
        print("FINALIZE FAILED: \(url.path)")
    }
}
