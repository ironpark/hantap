// Draws the hantap app icon and writes Resources/AppIcon.icns plus a 1024px
// preview at assets/icon.png.
//   swift scripts/make-icon.swift
// Layout follows the macOS icon grid: 1024 canvas, 824 squircle inset by 100.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Superellipse (n = 5) — close to Apple's continuous-corner icon shape.
func squircle(_ r: NSRect, n: CGFloat = 5) -> NSBezierPath {
    let p = NSBezierPath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / n), c)
        let y = cy + b * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: NSPoint(x: x, y: y)) : p.line(to: NSPoint(x: x, y: y))
    }
    p.close()
    return p
}

func drawText(_ s: String, font: NSFont, color: NSColor, center: NSPoint) {
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let size = attr.size()
    attr.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
}

func drawIcon() {
    // Background squircle: deep blue gradient.
    let bg = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bgPath = squircle(bg)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0x2B3FD6).setFill()
    bgPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x5B7CFF), color(0x3048E0), color(0x1C2A9E)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: bgPath, angle: -90)

    // Tap pulse: rounded outlines expanding from the key.
    let keyBase = NSRect(x: 242, y: 222, width: 540, height: 520)
    for (inset, alpha) in [(CGFloat(-44), CGFloat(0.42)), (-86, 0.18)] {
        let ring = NSBezierPath(roundedRect: keyBase.insetBy(dx: inset, dy: inset),
                                xRadius: 96 - inset, yRadius: 96 - inset)
        ring.lineWidth = 14
        color(0xFFFFFF, alpha).setStroke()
        ring.stroke()
    }

    // Keycap: side (base) then top surface.
    let base = keyBase
    NSGraphicsContext.saveGraphicsState()
    let keyShadow = NSShadow()
    keyShadow.shadowColor = color(0x0A1250, 0.45)
    keyShadow.shadowOffset = NSSize(width: 0, height: -18)
    keyShadow.shadowBlurRadius = 30
    keyShadow.set()
    color(0xAEB7CC).setFill()
    NSBezierPath(roundedRect: base, xRadius: 96, yRadius: 96).fill()
    NSGraphicsContext.restoreGraphicsState()

    let top = NSRect(x: 266, y: 276, width: 492, height: 448)
    let topPath = NSBezierPath(roundedRect: top, xRadius: 80, yRadius: 80)
    NSGradient(colors: [color(0xFFFFFF), color(0xE9EDF5)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: topPath, angle: -90)

    // CapsLock LED, glowing green.
    let led = NSRect(x: top.minX + 44, y: top.maxY - 76, width: 34, height: 34)
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0x34E36A, 0.9)
    glow.shadowBlurRadius = 22
    glow.set()
    color(0x30D158).setFill()
    NSBezierPath(ovalIn: led).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Legends: 한 (top-left) / A (bottom-right) with a diagonal divider.
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: top.maxX - 120, y: top.maxY - 70))
    divider.line(to: NSPoint(x: top.minX + 120, y: top.minY + 70))
    divider.lineWidth = 10
    divider.lineCapStyle = .round
    color(0xC5CCDA).setStroke()
    divider.stroke()

    let hangul = NSFont(name: "AppleSDGothicNeo-Heavy", size: 230)
        ?? NSFont(name: "AppleSDGothicNeo-Bold", size: 230)!
    drawText("한", font: hangul, color: color(0x1B2370), center: NSPoint(x: top.minX + 180, y: top.midY + 34))

    let latinBase = NSFont.systemFont(ofSize: 200, weight: .heavy)
    let latin = latinBase.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 200) } ?? latinBase
    drawText("A", font: latin, color: color(0x6B7591), center: NSPoint(x: top.maxX - 136, y: top.midY - 92))
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(px) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("hantap-\(getpid()).iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let resources = root.appendingPathComponent("Resources")
let assets = root.appendingPathComponent("assets")
try fm.createDirectory(at: resources, withIntermediateDirectories: true)
try fm.createDirectory(at: assets, withIntermediateDirectories: true)
try render(1024).write(to: assets.appendingPathComponent("icon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote Resources/AppIcon.icns and assets/icon.png")
