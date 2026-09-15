#!/usr/bin/env swift

// Generates the RightTrain app icon, web icons and Icon Composer layers from
// one set of geometry. Run from anywhere:
//
//   swift apps/clearsignal/ios/RightTrain/scripts/generate-righttrain-icons.swift
//
// The route mark: a white route (dot, line, arrowhead) chosen between two
// diverging tracks, on the app's forest green. Artwork is flat and fills the
// square: iOS 26 applies the corner mask and Liquid Glass lighting itself,
// so there are no baked shadows, highlights or rounded corners.
//
// The asset catalog icon (light / dark / tinted) is a flat stand-in. The
// shippable Liquid Glass icon is assembled in Icon Composer from the layers
// written to apps/clearsignal/design/app-icon/ (see the README there).

import AppKit
import CoreGraphics
import Foundation
import ImageIO

// MARK: - Paths

private let scriptURL = URL(fileURLWithPath: #filePath)
private let iosProjectURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let clearsignalURL = iosProjectURL.deletingLastPathComponent().deletingLastPathComponent()
private let appIconURL = iosProjectURL.appendingPathComponent("RightTrain/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
private let webIconURL = clearsignalURL.appendingPathComponent("frontend/public/icons", isDirectory: true)
private let layersURL = clearsignalURL.appendingPathComponent("design/app-icon", isDirectory: true)

// MARK: - Geometry (1024 canvas, y down)
//
// Mirrored by RightTrainRouteMark in the app; keep the two in step.

private enum Mark {
    static let stroke: CGFloat = 64

    static func upperTrack(_ p: (CGFloat, CGFloat) -> CGPoint) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: p(138, 280))
        path.addLine(to: p(238, 280))
        path.addCurve(to: p(378, 392), control1: p(306, 280), control2: p(314, 392))
        path.addLine(to: p(708, 392))
        return path
    }

    static func lowerTrack(_ p: (CGFloat, CGFloat) -> CGPoint) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: p(138, 744))
        path.addLine(to: p(238, 744))
        path.addCurve(to: p(378, 632), control1: p(306, 744), control2: p(314, 632))
        path.addLine(to: p(708, 632))
        return path
    }

    static func routeLine(_ p: (CGFloat, CGFloat) -> CGPoint) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: p(188, 512))
        path.addLine(to: p(858, 512))
        return path
    }

    static func arrowHead(_ p: (CGFloat, CGFloat) -> CGPoint) -> CGMutablePath {
        let path = CGMutablePath()
        path.move(to: p(814, 440))
        path.addLine(to: p(888, 512))
        path.addLine(to: p(814, 584))
        return path
    }

    /// Origin dot: centre and diameter.
    static let dot = (x: CGFloat(200), y: CGFloat(512), diameter: CGFloat(144))
}

// MARK: - Appearances

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: white, green: white, blue: white, alpha: alpha)
}

private struct Appearance {
    var name: String
    var backgroundTop: CGColor
    var backgroundBottom: CGColor
    var track: CGColor
    var route: CGColor
}

/// Forest green is the app's `RightTrainGood` (#0E4A30 / #4AC785).
private let light = Appearance(name: "Light", backgroundTop: rgb(0x17704A), backgroundBottom: rgb(0x0E4A30), track: gray(1, 0.38), route: gray(1))
private let dark = Appearance(name: "Dark", backgroundTop: rgb(0x10261C), backgroundBottom: rgb(0x07140E), track: rgb(0x4AC785, 0.38), route: rgb(0x4AC785))
/// Strictly grayscale: iOS applies the user's tint to its luminance.
private let tinted = Appearance(name: "Tinted", backgroundTop: gray(0.12), backgroundBottom: gray(0.04), track: gray(0.42), route: gray(1))

// MARK: - Rendering

private enum Layers {
    case all
    case backgroundOnly
}

private func render(_ appearance: Appearance, size: Int, layers: Layers = .all) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGImageByteOrderInfo.order32Big.rawValue
    ) else {
        throw NSError(domain: "RightTrainIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
    }

    let scale = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [appearance.backgroundTop, appearance.backgroundBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: CGFloat(size)), options: [])

    if case .all = layers {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(Mark.stroke * scale)

        for path in [Mark.upperTrack(p), Mark.lowerTrack(p)] {
            context.addPath(path)
            context.setStrokeColor(appearance.track)
            context.strokePath()
        }
        for path in [Mark.routeLine(p), Mark.arrowHead(p)] {
            context.addPath(path)
            context.setStrokeColor(appearance.route)
            context.strokePath()
        }
        let radius = Mark.dot.diameter / 2
        context.setFillColor(appearance.route)
        context.fillEllipse(in: CGRect(
            x: (Mark.dot.x - radius) * scale,
            y: (Mark.dot.y - radius) * scale,
            width: Mark.dot.diameter * scale,
            height: Mark.dot.diameter * scale
        ))
    }

    guard let image = context.makeImage() else {
        throw NSError(domain: "RightTrainIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create image"])
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "RightTrainIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "RightTrainIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not finalize PNG"])
    }
    print("Wrote \(url.path.replacingOccurrences(of: clearsignalURL.path + "/", with: ""))")
}

// MARK: - Icon Composer SVG layers

private func svgPathData(_ path: CGPath) -> String {
    var parts: [String] = []
    func f(_ v: CGFloat) -> String { String(format: "%g", Double(v)) }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
            parts.append("M\(f(points[0].x)) \(f(points[0].y))")
        case .addLineToPoint:
            parts.append("L\(f(points[0].x)) \(f(points[0].y))")
        case .addCurveToPoint:
            parts.append("C\(f(points[0].x)) \(f(points[0].y)) \(f(points[1].x)) \(f(points[1].y)) \(f(points[2].x)) \(f(points[2].y))")
        case .addQuadCurveToPoint:
            parts.append("Q\(f(points[0].x)) \(f(points[0].y)) \(f(points[1].x)) \(f(points[1].y))")
        case .closeSubpath:
            parts.append("Z")
        @unknown default:
            break
        }
    }
    return parts.joined(separator: " ")
}

private func writeSVG(_ body: String, to url: URL) throws {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
    \(body)
    </svg>

    """
    try svg.write(to: url, atomically: true, encoding: .utf8)
    print("Wrote \(url.path.replacingOccurrences(of: clearsignalURL.path + "/", with: ""))")
}

private func strokedPath(_ path: CGPath) -> String {
    "  <path d=\"\(svgPathData(path))\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"\(Int(Mark.stroke))\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
}

// MARK: - Output

private func unitPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// Asset catalog: one 1024 image per appearance; the system derives sizes.
try FileManager.default.createDirectory(at: appIconURL, withIntermediateDirectories: true)
for existing in try FileManager.default.contentsOfDirectory(at: appIconURL, includingPropertiesForKeys: nil)
where existing.pathExtension == "png" {
    try FileManager.default.removeItem(at: existing)
}
for appearance in [light, dark, tinted] {
    try writePNG(render(appearance, size: 1024), to: appIconURL.appendingPathComponent("AppIcon-\(appearance.name).png"))
}
let contents = """
{
  "images" : [
    {
      "filename" : "AppIcon-Light.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-Tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: appIconURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// Web: the light icon at the sizes the frontend references.
try FileManager.default.createDirectory(at: webIconURL, withIntermediateDirectories: true)
for px in [32, 60, 120, 180, 512, 1024] {
    try writePNG(render(light, size: px), to: webIconURL.appendingPathComponent("righttrain-icon-\(px).png"))
}

// Icon Composer layers, bottom to top. Colour and opacity per appearance are
// set in Icon Composer (see README.md), so shapes are exported in white.
try FileManager.default.createDirectory(at: layersURL, withIntermediateDirectories: true)
try writePNG(render(light, size: 1024, layers: .backgroundOnly), to: layersURL.appendingPathComponent("0-background.png"))
try writeSVG(
    [Mark.upperTrack(unitPoint), Mark.lowerTrack(unitPoint)].map(strokedPath).joined(separator: "\n"),
    to: layersURL.appendingPathComponent("1-tracks.svg")
)
let dotRadius = Mark.dot.diameter / 2
try writeSVG(
    [Mark.routeLine(unitPoint), Mark.arrowHead(unitPoint)].map(strokedPath).joined(separator: "\n")
        + "\n  <circle cx=\"\(Int(Mark.dot.x))\" cy=\"\(Int(Mark.dot.y))\" r=\"\(Int(dotRadius))\" fill=\"#FFFFFF\"/>",
    to: layersURL.appendingPathComponent("2-route.svg")
)
