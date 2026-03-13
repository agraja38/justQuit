import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent("justQuit.iconset", isDirectory: true)
let resourceURL = root
    .appendingPathComponent("AppBundle", isDirectory: true)
    .appendingPathComponent("Contents", isDirectory: true)
    .appendingPathComponent("Resources", isDirectory: true)
let icnsURL = resourceURL.appendingPathComponent("justQuit.icns")

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resourceURL, withIntermediateDirectories: true)

let backgroundTop = NSColor(calibratedRed: 0.99, green: 0.79, blue: 0.42, alpha: 1)
let backgroundBottom = NSColor(calibratedRed: 0.93, green: 0.47, blue: 0.17, alpha: 1)
let letterColor = NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.07, alpha: 1)
let glossColor = NSColor(calibratedWhite: 1, alpha: 0.22)

for (size, fileName) in sizes {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let cornerRadius = rect.width * 0.23
        let roundedRect = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        NSGraphicsContext.current?.imageInterpolation = .high

        let gradient = NSGradient(starting: backgroundTop, ending: backgroundBottom)
        gradient?.draw(in: roundedRect, angle: -90)

        glossColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: rect.minX + rect.width * 0.08,
                y: rect.midY,
                width: rect.width * 0.84,
                height: rect.height * 0.24
            ),
            xRadius: rect.width * 0.1,
            yRadius: rect.width * 0.1
        ).fill()

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.18)
        shadow.shadowBlurRadius = rect.width * 0.06
        shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.02)
        shadow.set()

        let fontSize = rect.width * 0.60
        let font = NSFont(name: "Avenir Next Demi Bold", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: letterColor,
            .paragraphStyle: paragraphStyle
        ]

        let text = NSAttributedString(string: "Q", attributes: attributes)
        let textRect = NSRect(
            x: rect.minX,
            y: rect.minY + rect.height * 0.14,
            width: rect.width,
            height: rect.height * 0.66
        )
        text.draw(in: textRect)
        return true
    }

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "QuitKeeperIcon", code: 1)
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(fileName))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["--convert", "icns", "--output", icnsURL.path, iconsetURL.path]
try task.run()
task.waitUntilExit()

guard task.terminationStatus == 0 else {
    throw NSError(domain: "QuitKeeperIcon", code: Int(task.terminationStatus))
}
