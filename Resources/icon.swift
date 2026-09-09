// Draws Resources/icon.png. Run: swiftc -O Resources/icon.swift -o /tmp/mkicon && /tmp/mkicon Resources/icon.png && sips -z 1024 1024 Resources/icon.png

import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square tile with a margin, like other macOS icons.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = [NSColor(red: 0.16, green: 0.52, blue: 1.0, alpha: 1).cgColor,
              NSColor(red: 0.05, green: 0.36, blue: 0.85, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// White page.
let page = CGRect(x: 232, y: 212, width: 560, height: 600)
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.setFillColor(NSColor.white.cgColor)
ctx.addPath(CGPath(roundedRect: page, cornerWidth: 48, cornerHeight: 48, transform: nil))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Header strip across the top of the page.
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: page, cornerWidth: 48, cornerHeight: 48, transform: nil))
ctx.clip()
ctx.setFillColor(NSColor(red: 0.93, green: 0.35, blue: 0.30, alpha: 1).cgColor)
ctx.fill(CGRect(x: page.minX, y: page.maxY - 150, width: page.width, height: 150))
ctx.restoreGState()

// Binder rings.
ctx.setFillColor(NSColor.white.cgColor)
for x in [page.minX + 140, page.maxX - 140] {
    ctx.fillEllipse(in: CGRect(x: x - 30, y: page.maxY - 100, width: 60, height: 60))
}
ctx.setFillColor(NSColor(red: 0.05, green: 0.36, blue: 0.85, alpha: 1).cgColor)
for x in [page.minX + 140, page.maxX - 140] {
    ctx.fill(CGRect(x: x - 14, y: page.maxY - 70 - 4, width: 28, height: 110))
    ctx.addPath(CGPath(roundedRect: CGRect(x: x - 14, y: page.maxY - 74, width: 28, height: 110), cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.fillPath()
}

// Big day number.
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 360, weight: .bold),
    .foregroundColor: NSColor(white: 0.13, alpha: 1),
    .paragraphStyle: para,
]
let text = NSAttributedString(string: "9", attributes: attrs)
let textRect = CGRect(x: page.minX, y: page.minY + 40, width: page.width, height: 400)
text.draw(in: textRect)

image.unlockFocus()
let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
rep.size = NSSize(width: size, height: size)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"))
print("wrote icon.png", rep.pixelsWide, rep.pixelsHigh)
