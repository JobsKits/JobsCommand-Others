//
//  GenerateAppIcon.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let canvasSize = NSSize(width: 1024, height: 1024)
let canvas = NSImage(size: canvasSize)
canvas.lockFocus()

let backgroundRect = NSRect(x: 32, y: 32, width: 960, height: 960)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 1, green: 0.19, blue: 0.16, alpha: 1),
    NSColor(calibratedRed: 0.72, green: 0.01, blue: 0.03, alpha: 1)
])
gradient?.draw(in: backgroundPath, angle: -90)

let innerPath = NSBezierPath(ovalIn: NSRect(x: 202, y: 202, width: 620, height: 620))
NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
innerPath.fill()

if let symbol = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: "Jobs 计划任务"),
   let configured = symbol.withSymbolConfiguration(
       NSImage.SymbolConfiguration(pointSize: 560, weight: .bold)
           .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
   ) {
    let symbolSize = configured.size
    let symbolRect = NSRect(
        x: (canvasSize.width - symbolSize.width) / 2,
        y: (canvasSize.height - symbolSize.height) / 2 - 4,
        width: symbolSize.width,
        height: symbolSize.height
    )
    configured.draw(in: symbolRect)
}

canvas.unlockFocus()
guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法生成 App 图标 PNG。\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
