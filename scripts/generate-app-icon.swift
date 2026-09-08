import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func render(size: Int, dark: Bool = false) throws {
    let bitmap = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let teal = NSColor(srgbRed: 15 / 255, green: 118 / 255, blue: 110 / 255, alpha: 1)
    (dark ? NSColor(srgbRed: 0.04, green: 0.12, blue: 0.12, alpha: 1) : teal).setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    let paper = NSColor(srgbRed: 0.97, green: 0.98, blue: 0.97, alpha: 1)
    paper.setFill()
    NSBezierPath(roundedRect: NSRect(x: 226, y: 178, width: 572, height: 668), xRadius: 42, yRadius: 42).fill()
    teal.setFill()
    NSBezierPath(roundedRect: NSRect(x: 300, y: 651, width: 424, height: 106), xRadius: 12, yRadius: 12).fill()
    NSBezierPath(roundedRect: NSRect(x: 300, y: 330, width: 168, height: 242), xRadius: 12, yRadius: 12).fill()
    for y in [548, 464, 380] {
        NSBezierPath(roundedRect: NSRect(x: 516, y: y, width: 208, height: 24), xRadius: 12, yRadius: 12).fill()
    }
    NSBezierPath(roundedRect: NSRect(x: 300, y: 266, width: 424, height: 24), xRadius: 12, yRadius: 12).fill()
    NSGraphicsContext.restoreGraphicsState()
    let name = dark ? "AppIcon-dark.png" : "AppIcon-\(size).png"
    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

for size in [16, 32, 64, 128, 256, 512, 1024] { try render(size: size) }
try render(size: 1024, dark: true)
var images: [[String: Any]] = [
    ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon-1024.png"],
    ["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "AppIcon-dark.png",
     "appearances": [["appearance": "luminosity", "value": "dark"]]]
]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": "AppIcon-\(size * scale).png"])
    }
}
let metadata: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Generated native app icons.")
