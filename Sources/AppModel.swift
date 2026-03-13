import AppKit
import Combine
import Foundation

struct RunningAppInfo: Identifiable, Hashable {
    let processIdentifier: pid_t
    let name: String
    let bundleIdentifier: String
    let activationPolicy: NSApplication.ActivationPolicy
    let icon: NSImage?

    var id: String {
        "\(bundleIdentifier)-\(processIdentifier)"
    }

    var isMenuBarOrBackgroundApp: Bool {
        activationPolicy != .regular
    }
}

struct QuitProfile: Codable, Identifiable, Hashable {
    let name: String
    let excludedBundleIdentifiers: [String]
    let includedBackgroundBundleIdentifiers: [String]

    var id: String { name }
}

struct ExportedSettings: Codable {
    let excludedBundleIdentifiers: [String]
    let includedBackgroundBundleIdentifiers: [String]
    let profiles: [QuitProfile]
    let confirmLargeQuitsEnabled: Bool
    let confirmationThreshold: Int
    let countdownEnabled: Bool
    let countdownSeconds: Int
    let notificationsEnabled: Bool
    let hotkeyEnabled: Bool
    let launchAtLoginEnabled: Bool
    let updateFeedURLString: String
}

struct QuitSummary {
    let targetNames: [String]

    var count: Int {
        targetNames.count
    }

    var message: String {
        "Asked \(count) app(s) to quit: \(targetNames.joined(separator: ", "))"
    }
}

struct UpdateFeed: Codable, Equatable {
    let version: String
    let downloadURL: String
    let releaseNotesURL: String?
    let minimumSystemVersion: String?
    let notes: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var runningApps: [RunningAppInfo] = []

    @Published var excludedBundleIdentifiers: Set<String> = [] { didSet { persist() } }
    @Published var includedBackgroundBundleIdentifiers: Set<String> = [] { didSet { persist() } }
    @Published var profiles: [QuitProfile] = [] { didSet { persist() } }

    @Published var confirmLargeQuitsEnabled = true { didSet { persist() } }
    @Published var confirmationThreshold = 5 { didSet { persist() } }
    @Published var countdownEnabled = false { didSet { persist() } }
    @Published var countdownSeconds = 5 { didSet { persist() } }
    @Published var notificationsEnabled = true { didSet { persist() } }
    @Published var hotkeyEnabled = false { didSet { persist() } }
    @Published var launchAtLoginEnabled = false { didSet { persist() } }
    @Published var updateFeedURLString = "" { didSet { persist() } }
    @Published var firstRunCompleted = false { didSet { persist() } }

    @Published var statusMessage = "Ready"
    @Published var newProfileName = ""
    @Published var availableUpdate: UpdateFeed?
    @Published var updateErrorMessage = ""
    @Published var isInstallingUpdate = false

    private let workspace = NSWorkspace.shared
    private let defaultsPrefix = "justQuit."
    private var refreshCancellable: AnyCancellable?
    private var isLoading = true

    init() {
        loadPreferences()
        refreshApps()
        startRefreshing()
        isLoading = false
    }

    var regularApps: [RunningAppInfo] {
        runningApps.filter { !$0.isMenuBarOrBackgroundApp }
    }

    var menuBarApps: [RunningAppInfo] {
        runningApps.filter(\.isMenuBarOrBackgroundApp)
    }

    var quickToggleApps: [RunningAppInfo] {
        Array(runningApps.prefix(8))
    }

    var appsToQuit: [RunningAppInfo] {
        runningApps.filter { shouldQuit($0) }
    }

    var skippedAppCount: Int {
        runningApps.count - appsToQuit.count
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    func shouldQuit(_ app: RunningAppInfo) -> Bool {
        if app.isMenuBarOrBackgroundApp {
            return includedBackgroundBundleIdentifiers.contains(app.bundleIdentifier)
        }

        return !excludedBundleIdentifiers.contains(app.bundleIdentifier)
    }

    func isExcluded(_ app: RunningAppInfo) -> Bool {
        !shouldQuit(app)
    }

    func toggleProtection(for app: RunningAppInfo) {
        if app.isMenuBarOrBackgroundApp {
            if includedBackgroundBundleIdentifiers.contains(app.bundleIdentifier) {
                includedBackgroundBundleIdentifiers.remove(app.bundleIdentifier)
            } else {
                includedBackgroundBundleIdentifiers.insert(app.bundleIdentifier)
            }
        } else {
            if excludedBundleIdentifiers.contains(app.bundleIdentifier) {
                excludedBundleIdentifiers.remove(app.bundleIdentifier)
            } else {
                excludedBundleIdentifiers.insert(app.bundleIdentifier)
            }
        }
    }

    func refreshApps() {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier

        runningApps = workspace.runningApplications
            .filter { app in
                app.processIdentifier != currentProcessID &&
                !app.isTerminated &&
                app.bundleIdentifier != nil &&
                app.localizedName != nil
            }
            .map { app in
                RunningAppInfo(
                    processIdentifier: app.processIdentifier,
                    name: app.localizedName ?? "Unknown App",
                    bundleIdentifier: app.bundleIdentifier ?? "unknown.bundle.id",
                    activationPolicy: app.activationPolicy,
                    icon: app.icon
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func quitSummary() -> QuitSummary? {
        let targets = appsToQuit
        guard !targets.isEmpty else {
            statusMessage = "Nothing to quit"
            return nil
        }

        return QuitSummary(targetNames: targets.map(\.name))
    }

    func performQuitAll() -> QuitSummary? {
        let targets = appsToQuit

        guard !targets.isEmpty else {
            statusMessage = "Nothing to quit"
            return nil
        }

        for target in targets {
            workspace.runningApplications
                .first(where: { $0.processIdentifier == target.processIdentifier })?
                .terminate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refreshApps()
        }

        let summary = QuitSummary(targetNames: targets.map(\.name))
        statusMessage = summary.message
        return summary
    }

    func shouldAskForConfirmation(appCount: Int) -> Bool {
        confirmLargeQuitsEnabled && appCount >= confirmationThreshold
    }

    func saveCurrentAsProfile() {
        let trimmedName = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Type a profile name first."
            return
        }

        let profile = QuitProfile(
            name: trimmedName,
            excludedBundleIdentifiers: Array(excludedBundleIdentifiers).sorted(),
            includedBackgroundBundleIdentifiers: Array(includedBackgroundBundleIdentifiers).sorted()
        )

        profiles.removeAll { $0.name == trimmedName }
        profiles.append(profile)
        profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        newProfileName = ""
        statusMessage = "Saved profile \(profile.name)."
    }

    func applyProfile(_ profile: QuitProfile) {
        excludedBundleIdentifiers = Set(profile.excludedBundleIdentifiers)
        includedBackgroundBundleIdentifiers = Set(profile.includedBackgroundBundleIdentifiers)
        statusMessage = "Applied profile \(profile.name)."
    }

    func deleteProfile(_ profile: QuitProfile) {
        profiles.removeAll { $0.id == profile.id }
        statusMessage = "Deleted profile \(profile.name)."
    }

    func exportSettings(to url: URL) throws {
        let payload = ExportedSettings(
            excludedBundleIdentifiers: Array(excludedBundleIdentifiers).sorted(),
            includedBackgroundBundleIdentifiers: Array(includedBackgroundBundleIdentifiers).sorted(),
            profiles: profiles,
            confirmLargeQuitsEnabled: confirmLargeQuitsEnabled,
            confirmationThreshold: confirmationThreshold,
            countdownEnabled: countdownEnabled,
            countdownSeconds: countdownSeconds,
            notificationsEnabled: notificationsEnabled,
            hotkeyEnabled: hotkeyEnabled,
            launchAtLoginEnabled: launchAtLoginEnabled,
            updateFeedURLString: updateFeedURLString
        )

        let data = try JSONEncoder().encode(payload)
        try data.write(to: url)
        statusMessage = "Exported settings."
    }

    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(ExportedSettings.self, from: data)

        excludedBundleIdentifiers = Set(payload.excludedBundleIdentifiers)
        includedBackgroundBundleIdentifiers = Set(payload.includedBackgroundBundleIdentifiers)
        profiles = payload.profiles
        confirmLargeQuitsEnabled = payload.confirmLargeQuitsEnabled
        confirmationThreshold = payload.confirmationThreshold
        countdownEnabled = payload.countdownEnabled
        countdownSeconds = payload.countdownSeconds
        notificationsEnabled = payload.notificationsEnabled
        hotkeyEnabled = payload.hotkeyEnabled
        launchAtLoginEnabled = payload.launchAtLoginEnabled
        updateFeedURLString = payload.updateFeedURLString

        statusMessage = "Imported settings."
    }

    func checkForUpdates(silent: Bool = false) async {
        updateErrorMessage = ""

        let trimmedURL = updateFeedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
            if !silent {
                statusMessage = "Add a valid update feed URL first."
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let feed = try JSONDecoder().decode(UpdateFeed.self, from: data)

            guard feed.version.compare(currentVersion, options: .numeric) == .orderedDescending else {
                availableUpdate = nil
                if !silent {
                    statusMessage = "You're up to date."
                }
                return
            }

            if let minimumSystemVersion = feed.minimumSystemVersion, !isSystemVersionSatisfied(minimumSystemVersion) {
                availableUpdate = nil
                if !silent {
                    statusMessage = "Update \(feed.version) requires macOS \(minimumSystemVersion) or newer."
                }
                return
            }

            availableUpdate = feed
            statusMessage = "Update \(feed.version) is available."
        } catch {
            availableUpdate = nil
            updateErrorMessage = error.localizedDescription
            if !silent {
                statusMessage = "Could not check for updates."
            }
        }
    }

    func openAvailableUpdate() {
        guard let availableUpdate, let url = URL(string: availableUpdate.downloadURL) else {
            statusMessage = "No update download URL is available."
            return
        }

        workspace.open(url)
    }

    func markOnboardingCompleted() {
        firstRunCompleted = true
    }

    private func startRefreshing() {
        refreshCancellable = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshApps()
            }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard

        excludedBundleIdentifiers = Set(defaults.stringArray(forKey: key("excluded")) ?? [])
        includedBackgroundBundleIdentifiers = Set(defaults.stringArray(forKey: key("includedBackground")) ?? [])
        confirmLargeQuitsEnabled = defaults.object(forKey: key("confirmLargeQuitsEnabled")) as? Bool ?? true
        confirmationThreshold = defaults.object(forKey: key("confirmationThreshold")) as? Int ?? 5
        countdownEnabled = defaults.object(forKey: key("countdownEnabled")) as? Bool ?? false
        countdownSeconds = defaults.object(forKey: key("countdownSeconds")) as? Int ?? 5
        notificationsEnabled = defaults.object(forKey: key("notificationsEnabled")) as? Bool ?? true
        hotkeyEnabled = defaults.object(forKey: key("hotkeyEnabled")) as? Bool ?? false
        launchAtLoginEnabled = defaults.object(forKey: key("launchAtLoginEnabled")) as? Bool ?? false
        updateFeedURLString = defaults.string(forKey: key("updateFeedURLString")) ?? ""
        firstRunCompleted = defaults.object(forKey: key("firstRunCompleted")) as? Bool ?? false

        if let profilesData = defaults.data(forKey: key("profiles")),
           let decodedProfiles = try? JSONDecoder().decode([QuitProfile].self, from: profilesData) {
            profiles = decodedProfiles
        }
    }

    private func persist() {
        guard !isLoading else { return }

        let defaults = UserDefaults.standard
        defaults.set(Array(excludedBundleIdentifiers).sorted(), forKey: key("excluded"))
        defaults.set(Array(includedBackgroundBundleIdentifiers).sorted(), forKey: key("includedBackground"))
        defaults.set(confirmLargeQuitsEnabled, forKey: key("confirmLargeQuitsEnabled"))
        defaults.set(confirmationThreshold, forKey: key("confirmationThreshold"))
        defaults.set(countdownEnabled, forKey: key("countdownEnabled"))
        defaults.set(countdownSeconds, forKey: key("countdownSeconds"))
        defaults.set(notificationsEnabled, forKey: key("notificationsEnabled"))
        defaults.set(hotkeyEnabled, forKey: key("hotkeyEnabled"))
        defaults.set(launchAtLoginEnabled, forKey: key("launchAtLoginEnabled"))
        defaults.set(updateFeedURLString, forKey: key("updateFeedURLString"))
        defaults.set(firstRunCompleted, forKey: key("firstRunCompleted"))

        if let profilesData = try? JSONEncoder().encode(profiles) {
            defaults.set(profilesData, forKey: key("profiles"))
        }
    }

    private func key(_ suffix: String) -> String {
        defaultsPrefix + suffix
    }

    private func isSystemVersionSatisfied(_ minimumVersion: String) -> Bool {
        let parts = minimumVersion.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return true }
        let minor = parts.count > 1 ? parts[1] : 0
        let patch = parts.count > 2 ? parts[2] : 0
        let minimum = OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(minimum)
    }

}
