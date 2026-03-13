import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    let triggerQuitFlow: () -> Void
    let installUpdate: () -> Void
    @State private var searchText = ""
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                mainTab
                    .tabItem { Text("Apps") }
                    .tag(0)

                settingsTab
                    .tabItem { Text("Settings") }
                    .tag(1)

                profilesTab
                    .tabItem { Text("Profiles") }
                    .tag(2)
            }
            footer
                .padding(.bottom, 12)
        }
        .frame(minWidth: 760, minHeight: 690)
    }

    private var mainTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actionsBar
                appsPanel(title: "Apps You Can Protect From Quitting", apps: filtered(model.regularApps), emptyText: "No regular apps are open right now.")
                appsPanel(title: "Menu Bar and Background Apps", apps: filtered(model.menuBarApps), emptyText: "No menu bar or background apps detected.")
            }
            .padding(20)
        }
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("App Settings") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch at login", isOn: $model.launchAtLoginEnabled)
                        Toggle("Enable notifications", isOn: $model.notificationsEnabled)
                        Toggle("Enable global hotkey (\u{2303}\u{2325}Q)", isOn: $model.hotkeyEnabled)
                        Toggle("Confirm when quitting many apps", isOn: $model.confirmLargeQuitsEnabled)
                        Toggle("Enable countdown before quitting", isOn: $model.countdownEnabled)

                        if model.confirmLargeQuitsEnabled {
                            Stepper("Confirm when quitting \(model.confirmationThreshold)+ apps", value: $model.confirmationThreshold, in: 1 ... 50)
                        }

                        if model.countdownEnabled {
                            Stepper("Countdown seconds: \(model.countdownSeconds)", value: $model.countdownSeconds, in: 1 ... 30)
                        }

                        Picker("Menu bar icon style", selection: $model.menuBarIconStyle) {
                            ForEach(MenuBarIconStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("Recent Session Restore") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.lastRestoreSummaryText)
                            .foregroundStyle(.secondary)

                        Button("Restore Last Session") {
                            model.restoreLastSession()
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.lastRestoreSession == nil)
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("Updates") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button("Check for Updates") {
                                Task {
                                    await model.checkForUpdates()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isCheckingForUpdates || model.isInstallingUpdate)

                            Text(model.updateStatusText)
                                .foregroundStyle(.secondary)
                        }

                        if let availableUpdate = model.availableUpdate {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("New version available: \(availableUpdate.version)")
                                    .font(.headline)

                                if let sizeText = model.availableUpdateSizeText {
                                    Text("Update size: \(sizeText)")
                                        .foregroundStyle(.secondary)
                                }

                                if let notes = availableUpdate.notes, !notes.isEmpty {
                                    Text(notes)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 12) {
                                    Button(model.isInstallingUpdate ? "Updating..." : "Update Now") {
                                        installUpdate()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(model.isInstallingUpdate)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }

                        if !model.updateErrorMessage.isEmpty {
                            Text(model.updateErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("Backup & Transfer") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button("Export Settings") {
                                exportSettings()
                            }
                            .buttonStyle(.bordered)

                            Button("Import Settings") {
                                importSettings()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
    }

    private var profilesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Profiles") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            TextField("New profile name", text: $model.newProfileName)
                                .textFieldStyle(.roundedBorder)

                            Button("Save Current") {
                                model.saveCurrentAsProfile()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if model.profiles.isEmpty {
                            Text("No saved profiles yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.profiles) { profile in
                                HStack {
                                    Text(profile.name)
                                        .font(.headline)

                                    Spacer()

                                    Button("Apply") {
                                        model.applyProfile(profile)
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Delete") {
                                        model.deleteProfile(profile)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("justQuit")
                .font(.system(size: 30, weight: .bold))

            Text("Quit regular apps by default, and choose whether menu bar or background apps stay skipped or get included too.")
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                StatBadge(icon: "bolt.circle.fill", text: "Eligible now: \(model.appsToQuit.count) app(s)")
                StatBadge(icon: "lock.shield.fill", text: "Protected: \(model.regularApps.filter(model.isExcluded).count)")
                StatBadge(icon: "eye.slash.fill", text: "Background skipped: \(model.menuBarApps.filter(model.isExcluded).count)")
                StatBadge(icon: "checkmark.circle.fill", text: "Background included: \(model.menuBarApps.filter(model.shouldQuit).count)")
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private var actionsBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Quit All Eligible Apps") {
                    triggerQuitFlow()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)

                Button("Refresh") {
                    model.refreshApps()
                }
                .buttonStyle(.bordered)

                Button("Restore Last Session") {
                    model.restoreLastSession()
                }
                .buttonStyle(.bordered)
                .disabled(model.lastRestoreSession == nil)

                Spacer()

                Text(model.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 360, alignment: .trailing)
            }

            TextField("Search apps by name or bundle identifier", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func appsPanel(title: String, apps: [RunningAppInfo], emptyText: String) -> some View {
        GroupBox(title) {
            if apps.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(apps) { app in
                        AppRow(
                            app: app,
                            isProtected: model.isExcluded(app),
                            detail: model.isExcluded(app) ? protectedLabel(for: app) : "Will quit",
                            action: { model.toggleProtection(for: app) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var footer: some View {
        Text("Created by Agraja")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
    }

    private func filtered(_ apps: [RunningAppInfo]) -> [RunningAppInfo] {
        guard !searchText.isEmpty else { return apps }

        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func protectedLabel(for app: RunningAppInfo) -> String {
        return app.isMenuBarOrBackgroundApp ? "Skipped" : "Protected"
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "justQuit-settings.json"
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try model.exportSettings(to: url)
            } catch {
                model.statusMessage = "Could not export settings."
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try model.importSettings(from: url)
            } catch {
                model.statusMessage = "Could not import settings."
            }
        }
    }
}

private struct AppRow: View {
    let app: RunningAppInfo
    let isProtected: Bool
    let detail: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(icon: app.icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)

                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(detail)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isProtected ? .green : .orange)
                .frame(width: 90, alignment: .trailing)

            Toggle("", isOn: .init(
                get: { isProtected },
                set: { _ in action() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct AppIconView: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct StatBadge: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .labelStyle(.titleAndIcon)
    }
}
