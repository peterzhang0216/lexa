// Lexa 图标渲染器：swift design/make_icon.swift <A|B|C> <输出.png>
// A = 卡片叠 + Aa（推荐）  B = L 字母 monogram  C = 白卡 + 拾
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let variant = args[1].first else {
    print("usage: make_icon.swift <A|B|C> <out.png>"); exit(1)
}
let out = args[2]

let S: CGFloat = 1024
let accent   = NSColor(srgbRed: 0.35, green: 0.37, blue: 0.92, alpha: 1)      // #595EEB
let deepEnd  = NSColor(srgbRed: 0.24, green: 0.27, blue: 0.80, alpha: 1)      // 渐变深端
let lightEnd = NSColor(srgbRed: 0.44, green: 0.47, blue: 0.98, alpha: 1)      // 渐变浅端

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ns

// 背景：靛蓝对角渐变 + 左上柔光（导出时会整体垂直翻转一次，方向参数预先镜像）
NSGradient(colors: [lightEnd, deepEnd])!.draw(in: NSRect(x: 0, y: 0, width: S, height: S), angle: 55)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 0, y: 0, width: S, height: S),
          relativeCenterPosition: NSPoint(x: -0.35, y: -0.42))

func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

func drawString(_ text: String, size: CGFloat, weight: NSFont.Weight,
                color: NSColor, center: NSPoint, rounded: Bool) {
    var desc = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
    if rounded, let rd = desc.withDesign(.rounded) { desc = rd }
    let font = NSFont(descriptor: desc, size: size) ?? .systemFont(ofSize: size, weight: weight)
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let b = s.boundingRect(with: .zero, options: [.usesLineFragmentOrigin])
    s.draw(at: NSPoint(x: center.x - b.width / 2, y: center.y - b.height / 2))
}

func card(_ r: NSRect, radius: CGFloat, fill: NSColor, rotation: CGFloat, shadow: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: r.midX, yBy: r.midY)
    t.rotate(byDegrees: rotation)
    t.translateX(by: -r.midX, yBy: -r.midY)
    t.concat()
    if shadow {
        ctx.setShadow(offset: NSSize(width: 0, height: 26), blur: 70,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
    }
    fill.setFill()
    rounded(r, radius).fill()
    NSGraphicsContext.restoreGraphicsState()
}

switch variant {
case "A", "C":
    let backCard  = NSRect(x: 272, y: 168, width: 560, height: 640)
    let frontCard = NSRect(x: 192, y: 216, width: 560, height: 640)
    card(backCard, radius: 120, fill: NSColor.white.withAlphaComponent(0.30), rotation: 9, shadow: false)
    card(frontCard, radius: 120, fill: .white, rotation: -4, shadow: true)
    // 正面卡片内容：Aa 或 拾，底部三个小圆点呼应"进度"
    let glyph = variant == "A" ? "Aa" : "拾"
    drawString(glyph, size: glyph == "Aa" ? 300 : 330, weight: .bold,
               color: accent, center: NSPoint(x: 472, y: 480), rounded: variant == "A")
    for (i, alpha) in [0.25, 0.55, 1.0].enumerated() {
        let dot = NSBezierPath(ovalIn: NSRect(x: 400 + CGFloat(i) * 56, y: 726, width: 22, height: 22))
        accent.withAlphaComponent(alpha).setFill()
        dot.fill()
    }
case "B":
    drawString("L", size: 560, weight: .bold, color: .white,
               center: NSPoint(x: S / 2, y: S / 2 - 30), rounded: true)
    let dot = NSBezierPath(ovalIn: NSRect(x: 640, y: 640, width: 74, height: 74))
    NSColor.white.withAlphaComponent(0.9).setFill()
    dot.fill()
default: break
}

NSGraphicsContext.restoreGraphicsState()
// flipped 上下文写出的原始位图是上下颠倒的，导出时翻回来
let raw = ctx.makeImage()!
let flip = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                     bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
flip.translateBy(x: 0, y: S)
flip.scaleBy(x: 1, y: -1)
flip.draw(raw, in: CGRect(x: 0, y: 0, width: S, height: S))
let rep = NSBitmapImageRep(cgImage: flip.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
