#!/usr/bin/env swift
// 앱 아이콘을 그려 Resources/AppIcon.icns 로 만든다.
//
//   swift scripts/render-icon.swift            # Resources/AppIcon.icns, Resources/AppIcon.png
//
// 그릇과 김은 '점심', 오른쪽 아래 주사위는 '뽑기'다. SF Symbols 는 앱 아이콘에 쓸 수 없어 도형을 직접 그린다.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(size: Int) -> CGImage {
    let s = CGFloat(size) / 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)  // 이하 1024 기준 좌표, 원점은 왼쪽 아래

    // macOS 아이콘 격자: 1024 캔버스 안 824 정사각, 모서리 반경 약 185
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 그림자
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(tilePath); ctx.setFillColor(color(0xD9382A)); ctx.fillPath()
    ctx.restoreGState()

    // 바탕: 앱 강조색(빨강) 세로 그라데이션
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let background = CGGradient(colorsSpace: nil, colors: [color(0xF0644A), color(0xC92E1E)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    let cream = color(0xFFF7EE)

    // 김 세 줄
    ctx.setStrokeColor(color(0xFFF7EE, 0.9)); ctx.setLineWidth(30); ctx.setLineCap(.round)
    for x in [400.0, 512.0, 624.0] {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: 600))
        path.addCurve(to: CGPoint(x: x, y: 760), control1: CGPoint(x: x - 46, y: 650), control2: CGPoint(x: x + 46, y: 710))
        ctx.addPath(path); ctx.strokePath()
    }

    // 젓가락 (그릇 뒤로 비스듬히)
    ctx.setStrokeColor(color(0x7A2A1A)); ctx.setLineWidth(22)
    for (start, end) in [(CGPoint(x: 600, y: 520), CGPoint(x: 790, y: 770)), (CGPoint(x: 640, y: 505), CGPoint(x: 820, y: 735))] {
        ctx.move(to: start); ctx.addLine(to: end); ctx.strokePath()
    }

    // 그릇: 테두리 타원 + 아래 반원 몸통
    let bowl = CGMutablePath()
    bowl.move(to: CGPoint(x: 252, y: 540))
    bowl.addCurve(to: CGPoint(x: 512, y: 300), control1: CGPoint(x: 262, y: 400), control2: CGPoint(x: 380, y: 300))
    bowl.addCurve(to: CGPoint(x: 772, y: 540), control1: CGPoint(x: 644, y: 300), control2: CGPoint(x: 762, y: 400))
    bowl.closeSubpath()
    ctx.addPath(bowl); ctx.setFillColor(cream); ctx.fillPath()
    // 그릇 굽
    ctx.setFillColor(cream)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 432, y: 262, width: 160, height: 52), cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.fillPath()
    // 그릇 입구 (안쪽이 살짝 보이게)
    ctx.setFillColor(color(0xF2D9C4))
    ctx.fillEllipse(in: CGRect(x: 252, y: 512, width: 520, height: 60))
    // 그릇 띠
    ctx.setStrokeColor(color(0xD9382A, 0.85)); ctx.setLineWidth(16)
    let band = CGMutablePath()
    band.move(to: CGPoint(x: 300, y: 450))
    band.addQuadCurve(to: CGPoint(x: 724, y: 450), control: CGPoint(x: 512, y: 410))
    ctx.addPath(band); ctx.strokePath()

    // 주사위 (오른쪽 아래, 살짝 기울임) — 랜덤 추천
    ctx.saveGState()
    ctx.translateBy(x: 742, y: 262); ctx.rotate(by: -0.26)
    let die = CGRect(x: -96, y: -96, width: 192, height: 192)
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x000000, 0.25))
    ctx.addPath(CGPath(roundedRect: die, cornerWidth: 40, cornerHeight: 40, transform: nil))
    ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(color(0xC92E1E))
    for (x, y) in [(-48.0, 48.0), (0.0, 0.0), (48.0, -48.0)] {
        ctx.fillEllipse(in: CGRect(x: x - 22, y: y - 22, width: 44, height: 44))
    }
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try writePNG(render(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(render(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try writePNG(render(size: 1024), to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print(resources.appendingPathComponent("AppIcon.icns").path)
