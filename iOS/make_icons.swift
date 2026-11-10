// Builds the iPhone / iPad alternate app icons from the Mac icons in App/Resources/Icons.
// The Mac icons have a transparent margin and rounded corners; iOS wants a full-bleed opaque square
// (the system rounds it). For each icon: crop the opaque area, trim the rounded corners, fill the
// background with the colour of the icon's edge and write a 1024×1024 PNG into
// iOS/PkMacIOS/Assets.xcassets/AppIcon-<id>.appiconset/ with its Contents.json.
// Run from the repository root:  xcrun swift iOS/make_icons.swift <id>...
// Only icons whose source is newer than the generated PNG are redone.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let fm = FileManager.default
let sourceDir = URL(fileURLWithPath: "App/Resources/Icons")
let catalog = URL(fileURLWithPath: "iOS/PkMacIOS/Assets.xcassets")
let side = 1024

func modified(_ url: URL) -> Date? {
    (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

func loadRGBA(_ url: URL) -> (CGContext, Int, Int)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (ctx, w, h)
}

func makeIcon(id: String) -> Bool {
    let src = sourceDir.appendingPathComponent("\(id).png")
    let set = catalog.appendingPathComponent("AppIcon-\(id).appiconset")
    let out = set.appendingPathComponent("AppIcon-\(id).png")
    guard let srcDate = modified(src) else {
        print("make_icons: manca \(src.path)")
        return false
    }
    if let outDate = modified(out), outDate >= srcDate,
       fm.fileExists(atPath: set.appendingPathComponent("Contents.json").path) {
        return true
    }
    guard let loaded = loadRGBA(src), let data = loaded.0.data else {
        print("make_icons: non riesco a leggere \(src.path)")
        return false
    }
    let (ctx, w, h) = loaded
    let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

    // Bounding box of the opaque pixels (alpha > 200). Bitmap row 0 is the top of the image.
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where px[(y * w + x) * 4 + 3] > 200 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX > minX, maxY > minY else {
        print("make_icons: \(id).png è vuota")
        return false
    }
    // Trim the rounded corners.
    let bw = maxX - minX + 1, bh = maxY - minY + 1
    let inset = Int(Double(bw) * 0.075)
    let crop = CGRect(x: minX + inset, y: minY + inset, width: bw - 2 * inset, height: bh - 2 * inset)

    // Background: the colour at the middle of the cropped top edge.
    let sx = Int(crop.midX), sy = Int(crop.minY) + 2
    let i = (sy * w + sx) * 4
    let a = max(CGFloat(px[i + 3]) / 255, 0.001)
    let bg = CGColor(srgbRed: CGFloat(px[i]) / 255 / a, green: CGFloat(px[i + 1]) / 255 / a,
                     blue: CGFloat(px[i + 2]) / 255 / a, alpha: 1)

    guard let full = ctx.makeImage(), let cropped = full.cropping(to: crop),
          let canvas = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        print("make_icons: ritaglio fallito per \(id)")
        return false
    }
    canvas.interpolationQuality = .high
    canvas.setFillColor(bg)
    canvas.fill(CGRect(x: 0, y: 0, width: side, height: side))
    canvas.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let result = canvas.makeImage() else { return false }

    try? fm.createDirectory(at: set, withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, result, nil)
    guard CGImageDestinationFinalize(dest) else {
        print("make_icons: non riesco a scrivere \(out.path)")
        return false
    }
    let contents = """
    {
      "images" : [
        { "filename" : "AppIcon-\(id).png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
    try? contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("make_icons: AppIcon-\(id)")
    return true
}

let ids = Array(CommandLine.arguments.dropFirst())
var ok = true
for id in ids {
    if !makeIcon(id: id) { ok = false }
}
exit(ok ? 0 : 1)
