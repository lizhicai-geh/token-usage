#!/usr/bin/env swift
import AppKit

// Discrete tiles echo the activity grid; a turned jade tile marks an active token.
// Keep the geometry shared
// across all macOS icon sizes, rendering at 4× for crisp small representations.
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let catalog = root.appendingPathComponent("App/Assets.xcassets")
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func roundedSquare(x: CGFloat, y: CGFloat, side: CGFloat, radius: CGFloat,
                   in context: CGContext) {
    context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: side, height: side),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

func renderIcon(pixels: Int) throws -> Data {
    let resolution = pixels * 4
    let context = CGContext(
        data: nil, width: resolution, height: resolution,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(resolution) / 1024, y: CGFloat(resolution) / 1024)

    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 184, cornerHeight: 184, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 16,
                      color: CGColor(gray: 0, alpha: 0.12))
    context.setFillColor(CGColor(srgbRed: 0.12, green: 0.15, blue: 0.13, alpha: 1))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()

    context.setFillColor(CGColor(srgbRed: 0.91, green: 0.93, blue: 0.88, alpha: 1))
    for (x, y): (CGFloat, CGFloat) in [(300, 300), (524, 300), (300, 524)] {
        roundedSquare(x: x, y: y, side: 176, radius: 28, in: context)
    }

    context.saveGState()
    context.translateBy(x: 612, y: 612)
    context.rotate(by: .pi / 4)
    context.setFillColor(CGColor(srgbRed: 0.52, green: 0.84, blue: 0.65, alpha: 1))
    roundedSquare(x: -88, y: -88, side: 176, radius: 28, in: context)
    context.restoreGState()

    let image = context.makeImage()!
    let output = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    output.interpolationQuality = .high
    output.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return NSBitmapImageRep(cgImage: output.makeImage()!)
        .representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try renderIcon(pixels: size * scale).write(to: iconSet.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac",
                       "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let info = ["author": "xcode", "version": 1] as [String: Any]
try JSONSerialization.data(withJSONObject: ["images": images, "info": info],
                           options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info],
                           options: [.prettyPrinted, .sortedKeys])
    .write(to: catalog.appendingPathComponent("Contents.json"))
print("Generated macOS AppIcon (16–1024 px).")
