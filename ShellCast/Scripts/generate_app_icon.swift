#!/usr/bin/env swift

// Generates a 1024x1024 app icon for ShellCast.
// Design: Dark rounded terminal window with green ">_" prompt.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let scale = CGFloat(size)

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil,
          width: size, height: size,
          bitsPerComponent: 8,
          bytesPerRow: size * 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    print("Failed to create CGContext")
    exit(1)
}

// Background: dark charcoal gradient
let bgColors: [CGFloat] = [
    0.08, 0.09, 0.12, 1.0,  // top: slightly lighter
    0.04, 0.05, 0.07, 1.0   // bottom: darker
]
let bgGradient = CGGradient(colorSpace: colorSpace, colorComponents: bgColors, locations: [0, 1], count: 2)!
ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: scale), end: CGPoint(x: 0, y: 0), options: [])

// Terminal window frame (rounded rect, slightly inset)
let inset: CGFloat = 80
let cornerRadius: CGFloat = 120
let termRect = CGRect(x: inset, y: inset, width: scale - inset * 2, height: scale - inset * 2)
let termPath = CGPath(roundedRect: termRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Terminal background: very dark with slight transparency
ctx.saveGState()
ctx.addPath(termPath)
ctx.clip()
let termColors: [CGFloat] = [
    0.06, 0.07, 0.10, 0.95,
    0.02, 0.03, 0.05, 0.95
]
let termGradient = CGGradient(colorSpace: colorSpace, colorComponents: termColors, locations: [0, 1], count: 2)!
ctx.drawLinearGradient(termGradient, start: CGPoint(x: 0, y: scale - inset), end: CGPoint(x: 0, y: inset), options: [])
ctx.restoreGState()

// Terminal border: subtle green glow
ctx.saveGState()
ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.2, 0.8, 0.4, 0.5])!)
ctx.setLineWidth(4)
ctx.addPath(termPath)
ctx.strokePath()
ctx.restoreGState()

// Title bar dots (red, yellow, green)
let dotY = scale - inset - 50
let dotRadius: CGFloat = 14
let dotColors: [(CGFloat, CGFloat, CGFloat)] = [
    (0.95, 0.30, 0.25),  // red
    (0.95, 0.75, 0.20),  // yellow
    (0.30, 0.85, 0.40),  // green
]
for (i, color) in dotColors.enumerated() {
    let dotX = inset + 55 + CGFloat(i) * 42
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [color.0, color.1, color.2, 1.0])!)
    ctx.fillEllipse(in: CGRect(x: dotX - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
}

// Draw ">_" prompt text using Core Graphics paths
// ">" character - large, centered
let promptX: CGFloat = 220
let promptY: CGFloat = 340  // from bottom (CG coords)
let chevronSize: CGFloat = 180

ctx.saveGState()
ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.2, 0.9, 0.4, 1.0])!)
ctx.setLineWidth(28)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// ">" chevron
ctx.beginPath()
ctx.move(to: CGPoint(x: promptX, y: promptY + chevronSize))
ctx.addLine(to: CGPoint(x: promptX + chevronSize * 0.6, y: promptY + chevronSize / 2))
ctx.addLine(to: CGPoint(x: promptX, y: promptY))
ctx.strokePath()

// "_" underscore cursor (blinking cursor look)
let cursorX = promptX + chevronSize * 0.75
let cursorY = promptY - 10
ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [0.2, 0.9, 0.4, 0.9])!)
ctx.fill(CGRect(x: cursorX, y: cursorY, width: 100, height: 24))

// Second line: faint "ssh" text (decorative)
ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.2, 0.9, 0.4, 0.2])!)
ctx.setLineWidth(6)
let lineY: CGFloat = 230
ctx.beginPath()
ctx.move(to: CGPoint(x: 220, y: lineY))
ctx.addLine(to: CGPoint(x: 580, y: lineY))
ctx.strokePath()

// Third line: even fainter
ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.2, 0.9, 0.4, 0.1])!)
ctx.beginPath()
ctx.move(to: CGPoint(x: 220, y: lineY - 60))
ctx.addLine(to: CGPoint(x: 480, y: lineY - 60))
ctx.strokePath()

ctx.restoreGState()

// Add subtle green glow around the prompt
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 30,
              color: CGColor(colorSpace: colorSpace, components: [0.2, 0.9, 0.4, 0.15])!)
ctx.setStrokeColor(CGColor(colorSpace: colorSpace, components: [0.2, 0.9, 0.4, 0.3])!)
ctx.setLineWidth(20)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.beginPath()
ctx.move(to: CGPoint(x: promptX, y: promptY + chevronSize))
ctx.addLine(to: CGPoint(x: promptX + chevronSize * 0.6, y: promptY + chevronSize / 2))
ctx.addLine(to: CGPoint(x: promptX, y: promptY))
ctx.strokePath()
ctx.restoreGState()

// Save as PNG
guard let image = ctx.makeImage() else {
    print("Failed to create image")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"
let url = URL(fileURLWithPath: outputPath)

guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("Failed to create image destination")
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    print("Failed to write PNG")
    exit(1)
}
print("Generated app icon: \(outputPath)")
