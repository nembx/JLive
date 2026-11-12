// Regenerate the app's geometric J + play mark with: swift scripts/generate-icons.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("JLive/Assets.xcassets")
let variants: [(String, NSColor, NSColor)] = [
    ("AppIcon", NSColor(red: 0.79, green: 0.96, blue: 0.48, alpha: 1), NSColor(red: 0.10, green: 0.17, blue: 0.12, alpha: 1)),
    ("AppIcon-Dark", NSColor(red: 0.07, green: 0.11, blue: 0.08, alpha: 1), NSColor(red: 0.79, green: 0.96, blue: 0.48, alpha: 1)),
    ("AppIcon-Tinted", .white, .black)
]
let icon = assets.appendingPathComponent("AppIcon.appiconset")
let brand = assets.appendingPathComponent("BrandMark.imageset")
try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: brand, withIntermediateDirectories: true)
for (name, background, ink) in variants {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(background.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.setStrokeColor(ink.cgColor)
    context.setLineWidth(118)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: 656, y: 747))
    context.addLine(to: CGPoint(x: 656, y: 412))
    context.addCurve(to: CGPoint(x: 346, y: 368), control1: CGPoint(x: 656, y: 212), control2: CGPoint(x: 388, y: 223))
    context.strokePath()
    context.setFillColor(ink.cgColor)
    context.move(to: CGPoint(x: 302, y: 512))
    context.addLine(to: CGPoint(x: 302, y: 762))
    context.addLine(to: CGPoint(x: 515, y: 637))
    context.closePath()
    context.fillPath()
    context.fillEllipse(in: CGRect(x: 767, y: 745, width: 62, height: 62))
    let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: icon.appendingPathComponent(name + ".png"))
    if name != "AppIcon-Tinted" { try png.write(to: brand.appendingPathComponent(name + ".png")) }
}
func write(_ value: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
try write(["info": ["author": "xcode", "version": 1]], to: assets.appendingPathComponent("Contents.json"))
try write(["info": ["author": "xcode", "version": 1], "images": [
    ["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
    ["filename": "AppIcon-Dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024", "appearances": [["appearance": "luminosity", "value": "dark"]]],
    ["filename": "AppIcon-Tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024", "appearances": [["appearance": "luminosity", "value": "tinted"]]]
]], to: icon.appendingPathComponent("Contents.json"))
try write(["info": ["author": "xcode", "version": 1], "images": [
    ["filename": "AppIcon.png", "idiom": "universal"],
    ["filename": "AppIcon-Dark.png", "idiom": "universal", "appearances": [["appearance": "luminosity", "value": "dark"]]]
]], to: brand.appendingPathComponent("Contents.json"))
