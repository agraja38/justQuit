import AppKit
import Foundation

enum AppUpdaterError: LocalizedError {
    case invalidDownloadURL
    case downloadFailed
    case extractedAppMissing
    case currentAppPathMissing
    case installerLaunchFailed

    var errorDescription: String? {
        switch self {
        case .invalidDownloadURL:
            return "The update feed does not contain a valid download URL."
        case .downloadFailed:
            return "The update could not be downloaded."
        case .extractedAppMissing:
            return "The downloaded update did not contain a valid app bundle."
        case .currentAppPathMissing:
            return "The current app path could not be found."
        case .installerLaunchFailed:
            return "The update installer could not be started."
        }
    }
}

@MainActor
final class AppUpdater {
    func install(update: UpdateFeed) async throws {
        guard let downloadURL = URL(string: update.downloadURL) else {
            throw AppUpdaterError.invalidDownloadURL
        }

        let currentAppURL = Bundle.main.bundleURL.standardizedFileURL
        guard currentAppURL.pathExtension == "app" else {
            throw AppUpdaterError.currentAppPathMissing
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("justQuit-update-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let archiveURL = temporaryDirectory.appendingPathComponent("justQuit-update.zip")
        let extractedDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)

        let (downloadedURL, _) = try await URLSession.shared.download(from: downloadURL)
        try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)

        try FileManager.default.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archiveURL.path, extractedDirectory.path]
        try unzip.run()
        unzip.waitUntilExit()

        guard unzip.terminationStatus == 0 else {
            throw AppUpdaterError.downloadFailed
        }

        let extractedAppURL = try findAppBundle(in: extractedDirectory)
        let scriptURL = temporaryDirectory.appendingPathComponent("install-update.sh")
        try installationScript(
            sourceAppURL: extractedAppURL,
            targetAppURL: currentAppURL
        ).write(to: scriptURL, atomically: true, encoding: .utf8)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        if FileManager.default.isWritableFile(atPath: currentAppURL.deletingLastPathComponent().path) {
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/zsh")
            launcher.arguments = ["-lc", "nohup \(quoted(scriptURL.path)) >/tmp/justquit-update.log 2>&1 &"]
            try launcher.run()
        } else {
            let appleScript = """
            do shell script "nohup /bin/zsh " & quoted form of "\(scriptURL.path)" & " >/tmp/justquit-update.log 2>&1 &" with administrator privileges
            """
            var error: NSDictionary?
            NSAppleScript(source: appleScript)?.executeAndReturnError(&error)
            if error != nil {
                throw AppUpdaterError.installerLaunchFailed
            }
        }

        NSApp.terminate(nil)
    }

    private func findAppBundle(in directory: URL) throws -> URL {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "app" {
                return fileURL
            }
        }

        throw AppUpdaterError.extractedAppMissing
    }

    private func installationScript(sourceAppURL: URL, targetAppURL: URL) -> String {
        """
        #!/bin/zsh
        set -euo pipefail
        sleep 1
        rm -rf \(quoted(targetAppURL.path))
        ditto \(quoted(sourceAppURL.path)) \(quoted(targetAppURL.path))
        open \(quoted(targetAppURL.path))
        """
    }

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
