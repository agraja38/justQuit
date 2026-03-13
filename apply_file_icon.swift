import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift apply_file_icon.swift <icon-path> <target-path>\n", stderr)
    exit(1)
}

let iconPath = CommandLine.arguments[1]
let targetPath = CommandLine.arguments[2]

guard let icon = NSImage(contentsOfFile: iconPath) else {
    fputs("Could not load icon at \(iconPath)\n", stderr)
    exit(2)
}

let success = NSWorkspace.shared.setIcon(icon, forFile: targetPath, options: [])
if !success {
    fputs("Failed to apply icon to \(targetPath)\n", stderr)
    exit(3)
}
