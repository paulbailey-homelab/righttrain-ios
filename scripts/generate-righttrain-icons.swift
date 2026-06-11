#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO

private struct AppIconImage: Decodable {
    let filename: String?
    let size: String
    let scale: String
}

private struct AppIconContents: Decodable {
    let images: [AppIconImage]
}

private let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let appIconURL = rootURL
    .appendingPathComponent("ios/RightTrain/RightTrain/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
private let webIconURL = rootURL
    .appendingPathComponent("frontend/public/icons", isDirectory: true)

private let navyTop = CGColor(red: 0x17 / 255.0, green: 0x28 / 255.0, blue: 0x3D / 255.0, alpha: 1)
private let navyBottom = CGColor(red: 0x08 / 255.0, green: 0x10 / 255.0, blue: 0x1F / 255.0, alpha: 1)
private let navyEdge = CGColor(red: 0x0F / 255.0, green: 0x17 / 255.0, blue: 0x2A / 255.0, alpha: 1)
private let track = CGColor(red: 0x9A / 255.0, green: 0xA8 / 255.0, blue: 0xB8 / 255.0, alpha: 0.78)
private let green = CGColor(red: 0x22 / 255.0, green: 0xC5 / 255.0, blue: 0x5E / 255.0, alpha: 1)

private func pixelSize(size: String, scale: String) -> Int {
    let pointValue = Double(size.split(separator: "x")[0]) ?? 0
    let scaleValue = Double(scale.trimmingCharacters(in: CharacterSet(charactersIn: "x"))) ?? 1
    return Int((pointValue * scaleValue).rounded())
}

private func drawRouteIcon(size: Int) throws -> CGImage {
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

    let s = CGFloat(size) / 1024
    func sx(_ value: CGFloat) -> CGFloat { value * s }

    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let backgroundGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [navyTop, navyBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

    context.setLineCap(.round)
    context.setLineJoin(.round)

    func strokePath(_ path: CGMutablePath, color: CGColor, width: CGFloat, shadowColor: CGColor, shadowBlur: CGFloat) {
        context.saveGState()
        context.addPath(path)
        context.setLineWidth(sx(width))
        context.setStrokeColor(color)
        context.setShadow(offset: CGSize(width: 0, height: sx(10)), blur: sx(shadowBlur), color: shadowColor)
        context.strokePath()
        context.restoreGState()
    }

    let upper = CGMutablePath()
    upper.move(to: CGPoint(x: sx(132), y: sx(270)))
    upper.addLine(to: CGPoint(x: sx(246), y: sx(270)))
    upper.addCurve(
        to: CGPoint(x: sx(386), y: sx(386)),
        control1: CGPoint(x: sx(314), y: sx(270)),
        control2: CGPoint(x: sx(322), y: sx(386))
    )
    upper.addLine(to: CGPoint(x: sx(728), y: sx(386)))

    let lower = CGMutablePath()
    lower.move(to: CGPoint(x: sx(132), y: sx(756)))
    lower.addLine(to: CGPoint(x: sx(246), y: sx(756)))
    lower.addCurve(
        to: CGPoint(x: sx(386), y: sx(638)),
        control1: CGPoint(x: sx(314), y: sx(756)),
        control2: CGPoint(x: sx(322), y: sx(638))
    )
    lower.addLine(to: CGPoint(x: sx(728), y: sx(638)))

    strokePath(upper, color: track, width: 48, shadowColor: CGColor(red: 0.76, green: 0.84, blue: 0.92, alpha: 0.22), shadowBlur: 18)
    strokePath(lower, color: track, width: 48, shadowColor: CGColor(red: 0.76, green: 0.84, blue: 0.92, alpha: 0.20), shadowBlur: 18)

    let arrowLine = CGMutablePath()
    arrowLine.move(to: CGPoint(x: sx(190), y: sx(512)))
    arrowLine.addLine(to: CGPoint(x: sx(878), y: sx(512)))
    strokePath(arrowLine, color: green, width: 50, shadowColor: CGColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 0.45), shadowBlur: 22)

    let arrowHead = CGMutablePath()
    arrowHead.move(to: CGPoint(x: sx(842), y: sx(450)))
    arrowHead.addLine(to: CGPoint(x: sx(916), y: sx(512)))
    arrowHead.addLine(to: CGPoint(x: sx(842), y: sx(574)))
    strokePath(arrowHead, color: green, width: 50, shadowColor: CGColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 0.42), shadowBlur: 22)

    context.saveGState()
    context.setFillColor(green)
    context.setShadow(offset: CGSize(width: 0, height: sx(10)), blur: sx(22), color: CGColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 0.44))
    context.fillEllipse(in: CGRect(x: sx(138), y: sx(446), width: sx(132), height: sx(132)))
    context.restoreGState()

    guard let image = context.makeImage() else {
        throw NSError(domain: "RightTrainIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create image"])
    }
    return image
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "RightTrainIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyPNGDictionary: [
            kCGImagePropertyPNGCompressionFilter: 0
        ]
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "RightTrainIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not finalize PNG"])
    }
}

try FileManager.default.createDirectory(at: webIconURL, withIntermediateDirectories: true)

private let contentsData = try Data(contentsOf: appIconURL.appendingPathComponent("Contents.json"))
private let contents = try JSONDecoder().decode(AppIconContents.self, from: contentsData)

for image in contents.images {
    guard let filename = image.filename else { continue }
    let px = pixelSize(size: image.size, scale: image.scale)
    let cgImage = try drawRouteIcon(size: px)
    try writePNG(cgImage, to: appIconURL.appendingPathComponent(filename))
    print("Wrote \(filename) (\(px)x\(px))")
}

for px in [32, 60, 120, 180, 512, 1024] {
    let cgImage = try drawRouteIcon(size: px)
    try writePNG(cgImage, to: webIconURL.appendingPathComponent("righttrain-icon-\(px).png"))
    print("Wrote righttrain-icon-\(px).png")
}
