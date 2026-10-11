// Convert the user's original desktop icon to opaque UIKit app icons.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Original AppIcon.icns is missing or unreadable")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
for (name, pixels) in [("AppIcon60x60@2x.png",120), ("AppIcon60x60@3x.png",180),
                       ("AppIcon76x76@2x.png",152), ("AppIcon83.5x83.5@2x.png",167)] {
    guard let bitmap = CGContext(data: nil, width: pixels, height: pixels,
       bitsPerComponent: 8, bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Icon bitmap allocation failed") }
    let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    NSColor.black.setFill(); bounds.fill()
    context.imageInterpolation = .high
    image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let encodedImage = bitmap.makeImage(),
          let encoder = CGImageDestinationCreateWithURL(destination.appendingPathComponent(name) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else { fatalError("PNG encoding failed") }
    CGImageDestinationAddImage(encoder, encodedImage, nil)
    guard CGImageDestinationFinalize(encoder) else { fatalError("PNG write failed") }
}
