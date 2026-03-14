import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private let notifications = NotificationManager()
    private let appUpdater = AppUpdater()
    private lazy var hotKeyManager = HotKeyManager { [weak self] in
        self?.triggerQuitFlow()
    }

    private var statusBarController: StatusBarController?
    private var window: NSWindow?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var countdownTimer: Timer?
    private var countdownRemaining = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ensureSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController(
            model: model,
            openGUI: { [weak self] in
                self?.showMainWindow()
            },
            triggerQuit: { [weak self] in
                self?.triggerQuitFlow()
            },
            cancelCountdown: { [weak self] in
                self?.cancelCountdown()
            },
            isCountdownActive: { [weak self] in
                (self?.countdownTimer) != nil
            }
        )

        bindSettings()

        Task {
            await model.checkForUpdates(silent: true)
        }

        if !model.firstRunCompleted {
            showMainWindow()
            showOnboarding()
            model.markOnboardingCompleted()
        }

        if LaunchMode.current == .quitNow {
            triggerQuitFlow()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
    }

    private func bindSettings() {
        model.$notificationsEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.notifications.requestAuthorizationIfNeeded()
                }
            }
            .store(in: &settingsCancellables)

        model.$hotkeyEnabled
            .sink { [weak self] enabled in
                self?.hotKeyManager.setEnabled(enabled)
            }
            .store(in: &settingsCancellables)

        model.$launchAtLoginEnabled
            .sink { [weak self] enabled in
                self?.applyLaunchAtLogin(enabled)
            }
            .store(in: &settingsCancellables)

        model.$menuBarIconStyle
            .sink { [weak self] style in
                self?.statusBarController?.applyIconStyle(style)
            }
            .store(in: &settingsCancellables)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }

        do {
            if enabled {
                try SMAppService.mainApp.register()
                model.statusMessage = "Launch at login enabled."
            } else {
                try SMAppService.mainApp.unregister()
                model.statusMessage = "Launch at login disabled."
            }
        } catch {
            model.statusMessage = "Launch at login could not be updated here."
        }
    }

    private func triggerQuitFlow() {
        if countdownTimer != nil {
            cancelCountdown()
            return
        }

        guard let summary = model.quitSummary() else { return }

        if model.shouldAskForConfirmation(appCount: summary.count) && !showConfirmation(for: summary) {
            model.statusMessage = "Quit cancelled."
            return
        }

        if model.countdownEnabled && model.countdownSeconds > 0 {
            beginCountdown(seconds: model.countdownSeconds) { [weak self] in
                self?.executeQuit()
            }
        } else {
            executeQuit()
        }
    }

    private func executeQuit() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownRemaining = 0
        statusBarController?.clearCountdownDisplay()

        guard let summary = model.performQuitAll() else { return }

        if model.notificationsEnabled {
            notifications.postQuitSummary(summary)
        }
    }

    private func beginCountdown(seconds: Int, completion: @escaping () -> Void) {
        countdownRemaining = seconds
        model.statusMessage = "Quitting in \(countdownRemaining) seconds..."
        statusBarController?.setCountdownDisplay(seconds: countdownRemaining)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { return }

                countdownRemaining -= 1

                if countdownRemaining <= 0 {
                    timer.invalidate()
                    countdownTimer = nil
                    statusBarController?.clearCountdownDisplay()
                    completion()
                } else {
                    model.statusMessage = "Quitting in \(countdownRemaining) seconds..."
                    statusBarController?.setCountdownDisplay(seconds: countdownRemaining)
                }
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownRemaining = 0
        statusBarController?.clearCountdownDisplay()
        model.statusMessage = "Countdown cancelled."
    }

    private func showConfirmation(for summary: QuitSummary) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Quit \(summary.count) app(s)?"
        alert.informativeText = summary.targetNames.joined(separator: ", ")
        alert.addButton(withTitle: "Quit Now")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showOnboarding() {
        let alert = NSAlert()
        alert.messageText = "Welcome to justQuit"
        alert.informativeText = "justQuit starts in the menu bar, supports profiles and restore sessions, and can trigger from the global hotkey \u{2303}\u{2325}Q."
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    private func ensureSingleInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let matchingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return !matchingApps.contains { $0.processIdentifier != currentProcessID && !$0.isTerminated }
    }

    private func showMainWindow() {
        if window == nil {
            let rootView = ContentView(
                model: model,
                triggerQuitFlow: { [weak self] in
                    self?.triggerQuitFlow()
                },
                installUpdate: { [weak self] in
                    self?.installAvailableUpdate()
                }
            )
            let hostingController = NSHostingController(rootView: rootView)

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "justQuit"
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            newWindow.contentViewController = hostingController
            newWindow.delegate = self
            window = newWindow
        }

        model.refreshApps()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func installAvailableUpdate() {
        guard let update = model.availableUpdate else {
            model.statusMessage = "No update is ready to install."
            return
        }

        model.isInstallingUpdate = true
        model.statusMessage = "Downloading update \(update.version)..."

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await appUpdater.install(update: update)
            } catch {
                model.isInstallingUpdate = false
                model.statusMessage = "Could not install the update."
                model.updateErrorMessage = error.localizedDescription
            }
        }
    }
}

private enum LaunchMode {
    case interactive
    case quitNow

    static var current: LaunchMode {
        ProcessInfo.processInfo.arguments.contains("--quit-now") ? .quitNow : .interactive
    }
}

@MainActor
private final class StatusBarController: NSObject {
    private let model: AppModel
    private let openGUI: () -> Void
    private let triggerQuit: () -> Void
    private let cancelCountdown: () -> Void
    private let isCountdownActive: () -> Bool
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(
        model: AppModel,
        openGUI: @escaping () -> Void,
        triggerQuit: @escaping () -> Void,
        cancelCountdown: @escaping () -> Void,
        isCountdownActive: @escaping () -> Bool
    ) {
        self.model = model
        self.openGUI = openGUI
        self.triggerQuit = triggerQuit
        self.cancelCountdown = cancelCountdown
        self.isCountdownActive = isCountdownActive
        super.init()
        configureStatusItem()
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            triggerQuit()
            return
        }

        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        default:
            if isCountdownActive() {
                cancelCountdown()
            } else {
                triggerQuit()
            }
        }
    }

    @objc private func openGUIFromMenu() {
        openGUI()
    }

    @objc private func quitEverythingFromMenu() {
        triggerQuit()
    }

    @objc private func restoreLastSessionFromMenu() {
        model.restoreLastSession()
    }

    @objc private func applyProfileFromMenu(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? QuitProfile else { return }
        model.applyProfile(profile)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.toolTip = "justQuit: left click quits eligible apps. Right click for more options."
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        applyIconStyle(model.menuBarIconStyle)
    }

    func setCountdownDisplay(seconds: Int) {
        statusItem.button?.image = nil
        statusItem.button?.attributedTitle = title(for: "\(seconds)", weight: .bold)
    }

    func clearCountdownDisplay() {
        applyIconStyle(model.menuBarIconStyle)
    }

    func applyIconStyle(_ style: MenuBarIconStyle) {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.attributedTitle = NSAttributedString(string: "")

        switch style {
        case .classicQ:
            button.attributedTitle = title(for: "Q", weight: .bold)
        case .badgeQ:
            button.image = badgeImage(text: "Q")
        case .compactJQ:
            button.attributedTitle = title(for: "JQ", weight: .bold)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let creditItem = NSMenuItem(title: "Created by Agraja", action: nil, keyEquivalent: "")
        creditItem.isEnabled = false
        menu.addItem(creditItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open GUI", action: #selector(openGUIFromMenu), keyEquivalent: ""))
        let quitAllItem = NSMenuItem(title: "Quit All Eligible Apps", action: #selector(quitEverythingFromMenu), keyEquivalent: "q")
        quitAllItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(quitAllItem)
        let restoreItem = NSMenuItem(title: "Restore Last Session", action: #selector(restoreLastSessionFromMenu), keyEquivalent: "")
        restoreItem.isEnabled = model.lastRestoreSession != nil
        menu.addItem(restoreItem)

        if !model.profiles.isEmpty {
            let profilesMenu = NSMenu()
            for profile in model.profiles {
                let item = NSMenuItem(title: profile.name, action: #selector(applyProfileFromMenu), keyEquivalent: "")
                item.target = self
                item.representedObject = profile
                profilesMenu.addItem(item)
            }

            let profilesItem = NSMenuItem(title: "Apply Profile", action: nil, keyEquivalent: "")
            menu.addItem(profilesItem)
            menu.setSubmenu(profilesMenu, for: profilesItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit justQuit", action: #selector(quitApp), keyEquivalent: ""))

        menu.items.forEach { $0.target = $0.target ?? self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func title(for text: String, weight: NSFont.Weight) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: weight),
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func badgeImage(text: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let circleRect = NSRect(x: 1, y: 1, width: 16, height: 16)
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.controlBackgroundColor,
            .paragraphStyle: paragraphStyle
        ]

        let textRect = NSRect(x: 0, y: 2, width: size.width, height: 12)
        text.draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
