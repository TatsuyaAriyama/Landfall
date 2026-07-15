import SwiftUI

@main
@MainActor
struct Main {
    static func main() {
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        render(IconPhoenix(), "A-phoenix", out)
        render(IconReturn(), "B-return", out)
        render(IconSkyline(), "C-skyline", out)
        render(IconPhoenixCoral(), "D-phoenix-coral", out)
    }

    static func render(_ view: some View, _ name: String, _ out: String) {
        // 1024フル + 120縮小(小サイズ視認性チェック)
        renderCard(view, name: "\(name)-1024", outDir: out, scale: 1)
        renderCard(view, name: "\(name)-120", outDir: out, scale: 120.0 / 1024.0)
    }
}
