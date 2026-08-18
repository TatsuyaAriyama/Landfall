#!/usr/bin/env swift

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("usage: build_home_island_sand_maps.swift <source.png> <output-directory>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let size = 1_024
let bytesPerPixel = 4
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

guard let source = NSImage(contentsOf: sourceURL)?.cgImage(
    forProposedRect: nil,
    context: nil,
    hints: nil
) else {
    fputs("could not read source image\n", stderr)
    exit(3)
}

var albedo = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
guard let albedoContext = CGContext(
    data: &albedo,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * bytesPerPixel,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else {
    fputs("could not create bitmap context\n", stderr)
    exit(4)
}
albedoContext.interpolationQuality = .high
albedoContext.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

var height = [Float](repeating: 0, count: size * size)
for index in 0..<height.count {
    let pixel = index * bytesPerPixel
    height[index] = (
        Float(albedo[pixel]) * 0.2126
            + Float(albedo[pixel + 1]) * 0.7152
            + Float(albedo[pixel + 2]) * 0.0722
    ) / 255
}

func sample(_ x: Int, _ y: Int) -> Float {
    let safeX = min(max(x, 0), size - 1)
    let safeY = min(max(y, 0), size - 1)
    return height[safeY * size + safeX]
}

func channel(_ value: Float) -> UInt8 {
    UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
}

func setPixel(_ bytes: inout [UInt8], index: Int, value: (Float, Float, Float)) {
    let pixel = index * bytesPerPixel
    bytes[pixel] = channel(value.0)
    bytes[pixel + 1] = channel(value.1)
    bytes[pixel + 2] = channel(value.2)
    bytes[pixel + 3] = 255
}

var normal = [UInt8](repeating: 0, count: albedo.count)
var roughness = [UInt8](repeating: 0, count: albedo.count)
var occlusion = [UInt8](repeating: 0, count: albedo.count)

for y in 0..<size {
    for x in 0..<size {
        let index = y * size + x
        let dx = sample(x + 2, y) - sample(x - 2, y)
        let dy = sample(x, y + 2) - sample(x, y - 2)
        var nx = -dx * 3.4
        var ny = -dy * 3.4
        var nz: Float = 1
        let inverseLength = 1 / sqrt(nx * nx + ny * ny + nz * nz)
        nx *= inverseLength
        ny *= inverseLength
        nz *= inverseLength
        setPixel(
            &normal,
            index: index,
            value: (nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz)
        )

        var neighborhood: Float = 0
        for offsetY in -2...2 where offsetY.isMultiple(of: 2) {
            for offsetX in -2...2 where offsetX.isMultiple(of: 2) {
                neighborhood += sample(x + offsetX, y + offsetY)
            }
        }
        neighborhood /= 9
        let localContrast = abs(height[index] - neighborhood)
        let grit = max(abs(dx), abs(dy))
        let rough = min(max(0.96 - localContrast * 0.75 - grit * 0.34, 0.70), 0.98)
        setPixel(&roughness, index: index, value: (rough, rough, rough))

        let cavity = min(max(0.93 + (height[index] - neighborhood) * 0.45, 0.80), 1)
        setPixel(&occlusion, index: index, value: (cavity, cavity, cavity))
    }
}

func makeImage(_ pixels: inout [UInt8]) -> CGImage {
    let context = CGContext(
        data: &pixels,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * bytesPerPixel,
        space: colorSpace,
        bitmapInfo: bitmapInfo.rawValue
    )!
    return context.makeImage()!
}

func write(_ image: CGImage, named name: String) {
    let url = outputDirectory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fputs("could not write \(url.path)\n", stderr)
        exit(5)
    }
    print(url.path)
}

write(albedoContext.makeImage()!, named: "home_island_sand_albedo.png")
write(makeImage(&normal), named: "home_island_sand_normal.png")
write(makeImage(&roughness), named: "home_island_sand_roughness.png")
write(makeImage(&occlusion), named: "home_island_sand_occlusion.png")
