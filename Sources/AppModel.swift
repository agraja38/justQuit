import AppKit
import Combine
import Foundation
import Darwin

enum HardwareProfile {
    static let isLaptop: Bool = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return false
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return false
        }

        let model = String(cString: buffer)
        return model.contains("MacBook")
    }()
}

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
    let menuBarIconStyleRawValue: String?
    let updateFeedURLString: String?
}

struct QuitSummary {
    let targetNames: [String]
    let targetBundleIdentifiers: [String]

    var count: Int {
        targetNames.count
    }

    var message: String {
        "Asked \(count) app(s) to quit: \(targetNames.joined(separator: ", "))"
    }
}

struct UpdateFeed: Decodable, Equatable {
    let version: String
    let downloadURL: String
    let releaseNotesURL: String?
    let minimumSystemVersion: String?
    let notes: String?
    let sizeBytes: Int64?

    private enum CodingKeys: String, CodingKey {
        case version
        case downloadURL
        case downloadUrl
        case releaseNotesURL
        case releaseNotesUrl
        case minimumSystemVersion
        case notes
        case sizeBytes
    }

    init(
        version: String,
        downloadURL: String,
        releaseNotesURL: String?,
        minimumSystemVersion: String?,
        notes: String?,
        sizeBytes: Int64?
    ) {
        self.version = version
        self.downloadURL = downloadURL
        self.releaseNotesURL = releaseNotesURL
        self.minimumSystemVersion = minimumSystemVersion
        self.notes = notes
        self.sizeBytes = sizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        downloadURL = try container.decodeIfPresent(String.self, forKey: .downloadURL)
            ?? container.decode(String.self, forKey: .downloadUrl)
        releaseNotesURL = try container.decodeIfPresent(String.self, forKey: .releaseNotesURL)
            ?? container.decodeIfPresent(String.self, forKey: .releaseNotesUrl)
        minimumSystemVersion = try container.decodeIfPresent(String.self, forKey: .minimumSystemVersion)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
    }
}

struct RestoreSession: Codable, Equatable {
    let bundleIdentifiers: [String]
    let appNames: [String]
    let createdAt: Date

    var count: Int {
        bundleIdentifiers.count
    }
}

enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable {
    case classicQ
    case badgeQ
    case compactJQ

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classicQ:
            return "Classic Q"
        case .badgeQ:
            return "Badge Q"
        case .compactJQ:
            return "Compact JQ"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let builtInUpdateFeedURLString = "https://raw.githubusercontent.com/agraja38/app-update-feeds/main/justquit/update.json"
    private static let alwaysProtectedBundleIdentifiers: Set<String> = ["com.apple.finder"]

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
    @Published var menuBarIconStyle: MenuBarIconStyle = .classicQ { didSet { persist() } }
    @Published var firstRunCompleted = false { didSet { persist() } }
    @Published var licenseKey = "" { didSet { persist() } }
    @Published private(set) var isProUnlocked = false
    @Published private(set) var licenseID = ""
    @Published private(set) var licenseStatusMessage = "Activate justQuit Pro to unlock countdowns, confirmation, custom menu bar icons, and profiles."
    @Published private(set) var appliedProfileID = "" { didSet { persist() } }

    @Published var statusMessage = "Ready"
    @Published var newProfileName = ""
    @Published var availableUpdate: UpdateFeed?
    @Published var availableUpdateSizeBytes: Int64?
    @Published var updateErrorMessage = ""
    @Published var isInstallingUpdate = false
    @Published var isCheckingForUpdates = false
    @Published var hasCheckedForUpdates = false
    @Published private(set) var lastRestoreSession: RestoreSession?
    @Published private(set) var lastUpdateNotificationVersion: String?

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

    var isLaptopHardware: Bool {
        HardwareProfile.isLaptop
    }

    var updateFeedURL: URL {
        URL(string: Self.builtInUpdateFeedURLString)!
    }

    var proBadgeText: String {
        isProUnlocked ? "Pro active" : "Pro"
    }

    var updateStatusText: String {
        if isCheckingForUpdates {
            return "Checking for updates..."
        }

        if let availableUpdate {
            return "Version \(availableUpdate.version) is ready."
        }

        if hasCheckedForUpdates && updateErrorMessage.isEmpty {
            return "This is the latest version."
        }

        return "Current version: \(currentVersion)"
    }

    var availableUpdateSizeText: String? {
        guard let availableUpdateSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: availableUpdateSizeBytes, countStyle: .file)
    }

    func isAlwaysProtected(_ app: RunningAppInfo) -> Bool {
        Self.alwaysProtectedBundleIdentifiers.contains(app.bundleIdentifier)
    }

    var lastRestoreSummaryText: String {
        guard let lastRestoreSession else {
            return "No recent session yet."
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let timeText = formatter.localizedString(for: lastRestoreSession.createdAt, relativeTo: Date())
        return "\(lastRestoreSession.count) app(s) saved from \(timeText)."
    }

    func shouldQuit(_ app: RunningAppInfo) -> Bool {
        if isAlwaysProtected(app) {
            return false
        }

        if app.isMenuBarOrBackgroundApp {
            return includedBackgroundBundleIdentifiers.contains(app.bundleIdentifier)
        }

        return !excludedBundleIdentifiers.contains(app.bundleIdentifier)
    }

    func isExcluded(_ app: RunningAppInfo) -> Bool {
        !shouldQuit(app)
    }

    func toggleProtection(for app: RunningAppInfo) {
        guard !isAlwaysProtected(app) else { return }

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

        return QuitSummary(
            targetNames: targets.map(\.name),
            targetBundleIdentifiers: targets.map(\.bundleIdentifier)
        )
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

        lastRestoreSession = RestoreSession(
            bundleIdentifiers: targets.map(\.bundleIdentifier),
            appNames: targets.map(\.name),
            createdAt: Date()
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.refreshApps()
        }

        let summary = QuitSummary(
            targetNames: targets.map(\.name),
            targetBundleIdentifiers: targets.map(\.bundleIdentifier)
        )
        statusMessage = summary.message
        return summary
    }

    func restoreLastSession() {
        guard let lastRestoreSession, !lastRestoreSession.bundleIdentifiers.isEmpty else {
            statusMessage = "No recent session to restore."
            return
        }

        var reopenedCount = 0
        for bundleIdentifier in lastRestoreSession.bundleIdentifiers {
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                continue
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false

            workspace.openApplication(at: appURL, configuration: configuration)
            reopenedCount += 1
        }

        if reopenedCount == 0 {
            statusMessage = "Could not restore the recent session."
        } else {
            statusMessage = "Restored \(reopenedCount) app(s)."
        }
    }

    func shouldAskForConfirmation(appCount: Int) -> Bool {
        isProUnlocked && confirmLargeQuitsEnabled && appCount >= confirmationThreshold
    }

    func saveCurrentAsProfile() {
        guard isProUnlocked else {
            statusMessage = "Activate justQuit Pro to save profiles."
            return
        }

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
        guard isProUnlocked else {
            statusMessage = "Activate justQuit Pro to apply profiles."
            return
        }

        excludedBundleIdentifiers = Set(profile.excludedBundleIdentifiers)
        includedBackgroundBundleIdentifiers = Set(profile.includedBackgroundBundleIdentifiers)
        appliedProfileID = profile.id
        statusMessage = "Applied profile \(profile.name)."
    }

    func deleteProfile(_ profile: QuitProfile) {
        guard isProUnlocked else {
            statusMessage = "Activate justQuit Pro to manage profiles."
            return
        }

        profiles.removeAll { $0.id == profile.id }
        if appliedProfileID == profile.id {
            appliedProfileID = ""
        }
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
            menuBarIconStyleRawValue: menuBarIconStyle.rawValue,
            updateFeedURLString: nil
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
        if let rawValue = payload.menuBarIconStyleRawValue,
           let importedStyle = MenuBarIconStyle(rawValue: rawValue) {
            menuBarIconStyle = importedStyle
        }

        statusMessage = "Imported settings."
    }

    func checkForUpdates(silent: Bool = false) async {
        isCheckingForUpdates = true
        hasCheckedForUpdates = false
        updateErrorMessage = ""
        availableUpdateSizeBytes = nil
        defer {
            isCheckingForUpdates = false
            hasCheckedForUpdates = true
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: updateFeedURL)
            let feed = try JSONDecoder().decode(UpdateFeed.self, from: data)

            guard feed.version.compare(currentVersion, options: .numeric) == .orderedDescending else {
                availableUpdate = nil
                if !silent {
                    statusMessage = "This is the latest version."
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
            availableUpdateSizeBytes = try await resolveUpdateSize(for: feed)
            statusMessage = "Update \(feed.version) is available."
        } catch {
            availableUpdate = nil
            availableUpdateSizeBytes = nil
            updateErrorMessage = error.localizedDescription
            if !silent {
                statusMessage = "Could not check for updates."
            }
        }
    }

    func shouldNotifyAboutAvailableUpdate() -> Bool {
        guard let availableUpdate else { return false }
        return lastUpdateNotificationVersion != availableUpdate.version
    }

    func markAvailableUpdateNotified() {
        lastUpdateNotificationVersion = availableUpdate?.version
        persist()
    }

    func markOnboardingCompleted() {
        firstRunCompleted = true
    }

    func activateLicense() async {
        statusMessage = "Contacting the license server..."
        let result = await LicenseService.activate(licenseKey)
        applyLicenseResult(result)
        persist()
    }

    private func restoreLicenseState() {
        let result = LicenseService.validate(licenseKey)
        applyLicenseResult(result)
    }

    private func applyLicenseResult(_ result: LicenseValidationResult) {
        isProUnlocked = result.isValid
        licenseID = result.licenseID ?? ""
        licenseStatusMessage = result.message
        statusMessage = result.message

        if !result.isValid {
            menuBarIconStyle = .classicQ
        }
    }

    func removeLicense() {
        licenseKey = ""
        isProUnlocked = false
        licenseID = ""
        licenseStatusMessage = "Activate justQuit Pro to unlock countdowns, confirmation, custom menu bar icons, and profiles."
        statusMessage = "justQuit Pro license removed."
        menuBarIconStyle = .classicQ
        persist()
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
        licenseKey = defaults.string(forKey: key("licenseKey")) ?? ""
        licenseID = defaults.string(forKey: key("licenseID")) ?? ""
        appliedProfileID = defaults.string(forKey: key("appliedProfileID")) ?? ""
        if let rawValue = defaults.string(forKey: key("menuBarIconStyle")),
           let storedStyle = MenuBarIconStyle(rawValue: rawValue) {
            menuBarIconStyle = storedStyle
        }
        firstRunCompleted = defaults.object(forKey: key("firstRunCompleted")) as? Bool ?? false

        if let profilesData = defaults.data(forKey: key("profiles")),
           let decodedProfiles = try? JSONDecoder().decode([QuitProfile].self, from: profilesData) {
            profiles = decodedProfiles
        }

        if let restoreData = defaults.data(forKey: key("lastRestoreSession")),
           let decodedSession = try? JSONDecoder().decode(RestoreSession.self, from: restoreData) {
            lastRestoreSession = decodedSession
        }

        lastUpdateNotificationVersion = defaults.string(forKey: key("lastUpdateNotificationVersion"))
        restoreLicenseState()
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
        defaults.set(menuBarIconStyle.rawValue, forKey: key("menuBarIconStyle"))
        defaults.set(firstRunCompleted, forKey: key("firstRunCompleted"))
        defaults.set(licenseKey, forKey: key("licenseKey"))
        defaults.set(licenseID, forKey: key("licenseID"))
        defaults.set(appliedProfileID, forKey: key("appliedProfileID"))

        if let profilesData = try? JSONEncoder().encode(profiles) {
            defaults.set(profilesData, forKey: key("profiles"))
        }

        if let restoreData = try? JSONEncoder().encode(lastRestoreSession) {
            defaults.set(restoreData, forKey: key("lastRestoreSession"))
        }

        defaults.set(lastUpdateNotificationVersion, forKey: key("lastUpdateNotificationVersion"))
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

    private func resolveUpdateSize(for feed: UpdateFeed) async throws -> Int64? {
        if let sizeBytes = feed.sizeBytes {
            return sizeBytes
        }

        guard let url = URL(string: feed.downloadURL) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }

        if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let sizeBytes = Int64(contentLength) {
            return sizeBytes
        }

        return nil
    }

}
