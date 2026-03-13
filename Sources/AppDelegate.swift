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

        if !model.updateFeedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                await model.checkForUpdates(silent: true)
            }
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
        alert.informativeText = "justQuit starts in the menu bar, supports profiles and quick toggles, and can trigger from the global hotkey \u{2303}\u{2325}Q."
        alert.addButton(withTitle: "Got it")
        alert.runModal()
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

    @objc private func cancelCountdownFromMenu() {
        cancelCountdown()
    }

    @objc private func refreshAppsFromMenu() {
        model.refreshApps()
    }

    @objc private func toggleQuickProtection(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? RunningAppInfo else { return }
        model.toggleProtection(for: app)
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

        button.attributedTitle = title(for: "Q")
        button.toolTip = "justQuit: left click quits eligible apps. Right click for more options."
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func setCountdownDisplay(seconds: Int) {
        statusItem.button?.attributedTitle = title(for: "\(seconds)")
    }

    func clearCountdownDisplay() {
        statusItem.button?.attributedTitle = title(for: "Q")
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
        menu.addItem(NSMenuItem(title: "Cancel Countdown", action: #selector(cancelCountdownFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Apps", action: #selector(refreshAppsFromMenu), keyEquivalent: ""))

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

        let quickToggleMenu = NSMenu()
        for app in model.quickToggleApps {
            let title = model.isExcluded(app) ? "Include \(app.name)" : "Protect \(app.name)"
            let item = NSMenuItem(title: title, action: #selector(toggleQuickProtection), keyEquivalent: "")
            item.target = self
            item.representedObject = app
            quickToggleMenu.addItem(item)
        }

        let quickToggleItem = NSMenuItem(title: "Quick Toggles", action: nil, keyEquivalent: "")
        menu.addItem(quickToggleItem)
        menu.setSubmenu(quickToggleMenu, for: quickToggleItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit justQuit", action: #selector(quitApp), keyEquivalent: ""))

        menu.items.forEach { $0.target = $0.target ?? self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func title(for text: String) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }
}
