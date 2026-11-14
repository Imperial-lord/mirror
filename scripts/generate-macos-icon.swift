// Rebuild the Mac icon from vector geometry, independently of the opaque iOS icon.
// Run from the repository root: swift scripts/generate-macos-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent("apps/macos/MirrorDesktop/Assets.xcassets/MacAppIcon.appiconset")
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
             (256, 1), (256, 2), (512, 1), (512, 2)]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func gray(_ value: CGFloat, alpha: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: space, components: [value, value, value, alpha])!
}
for (points, scale) in sizes {
  let pixels = points * scale
  let context = CGContext(data: nil, width: pixels, height: pixels,
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let factor = CGFloat(pixels) / 1024
  context.scaleBy(x: factor, y: factor)
  context.translateBy(x: 0, y: 1024)
  context.scaleBy(x: 1, y: -1)
  let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                    cornerWidth: 184, cornerHeight: 184, transform: nil)
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: 8), blur: 18,
                    color: gray(0, alpha: 0.22))
  context.addPath(tile)
  context.setFillColor(gray(0.04))
  context.fillPath()
  context.restoreGState()
  context.saveGState()
  context.addPath(tile)
  context.clip()
  let gradient = CGGradient(colorsSpace: space,
                            colors: [gray(0.095), gray(0.025)] as CFArray,
                            locations: [0, 1])!
  context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100),
                             end: CGPoint(x: 512, y: 924), options: [])
  context.restoreGState()
  context.addPath(tile)
  context.setStrokeColor(gray(1, alpha: 0.1))
  context.setLineWidth(2)
  context.strokePath()
  // Existing Mirror mark: a circular head and a semicircular reflection.
  context.setFillColor(gray(1))
  context.fillEllipse(in: CGRect(x: 380, y: 273, width: 264, height: 264))
  context.move(to: CGPoint(x: 364, y: 602))
  context.addLine(to: CGPoint(x: 660, y: 602))
  context.addArc(center: CGPoint(x: 512, y: 602), radius: 148,
                 startAngle: 0, endAngle: .pi, clockwise: false)
  context.closePath()
  context.fillPath()
  let url = output.appendingPathComponent("icon-\(points)@\(scale)x.png")
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  precondition(CGImageDestinationFinalize(destination), "Could not save \(url.lastPathComponent)")
}
print("Generated all 10 Mac icon sizes.")
