// swift scripts/make_icon.swift icon.png
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let s = CGFloat(size)
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// тень
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
path.fill()
NSGraphicsContext.restoreGraphicsState()

// фон
let gradient = NSGradient(colors: [
    NSColor(red: 1.00, green: 0.33, blue: 0.45, alpha: 1),
    NSColor(red: 0.62, green: 0.25, blue: 0.95, alpha: 1),
    NSColor(red: 0.22, green: 0.35, blue: 0.98, alpha: 1),
])!
gradient.draw(in: path, angle: -60)

// пластинка
let discRect = rect.insetBy(dx: 150, dy: 150)
NSColor.white.withAlphaComponent(0.16).setFill()
NSBezierPath(ovalIn: discRect).fill()
NSColor.white.withAlphaComponent(0.10).setStroke()
for i in 1...3 {
    let r = discRect.insetBy(dx: CGFloat(i) * 45, dy: CGFloat(i) * 45)
    let p = NSBezierPath(ovalIn: r); p.lineWidth = 6; p.stroke()
}

func drawSymbol(_ name: String, pointSize: CGFloat, in r: NSRect, alpha: CGFloat) {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    let tinted = NSImage(size: sym.size, flipped: false) { b in
        sym.draw(in: b)
        NSColor.white.withAlphaComponent(alpha).set()
        b.fill(using: .sourceAtop)
        return true
    }
    let ratio = min(r.width / sym.size.width, r.height / sym.size.height)
    let w = sym.size.width * ratio, h = sym.size.height * ratio
    tinted.draw(in: NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
}
drawSymbol("arrow.triangle.2.circlepath", pointSize: 400, in: rect.insetBy(dx: 120, dy: 120), alpha: 0.35)
drawSymbol("music.note", pointSize: 400, in: rect.insetBy(dx: 250, dy: 250), alpha: 1)

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
