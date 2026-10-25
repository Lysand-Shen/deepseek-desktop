import AppKit
import SwiftUI

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable private var localizer = Localizer.shared
    private let launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        Form {
            Section {
                Picker(L("Language"), selection: $localizer.preference) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text(L("Language"))
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text(L("Menus, Settings and dialogs switch right away. Menu items provided by macOS, and the default language of DeepSeek's web page, switch after a restart."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if localizer.needsRelaunch {
                        Spacer()
                        Button(L("Restart Now")) { NSApp.relaunch() }
                            .controlSize(.small)
                    }
                }
            }

            Section(L("Startup")) {
                Toggle(L("Open at Login"), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text(L("Allow DeepSeek in System Settings › General › Login Items."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Open System Settings")) { launchAtLogin.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle(L("Start in the background without opening the window"), isOn: $settings.startHidden)
                    .disabled(!settings.keepRunningInBackground)
            }

            Section(L("Window")) {
                Picker(L("Appearance"), selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle(L("Float on Top"), isOn: $settings.floatOnTop)
                Toggle(L("Keep running in the background after closing the window"), isOn: $settings.keepRunningInBackground)
            }

            Section {
                Toggle(L("Show icon in the Dock"), isOn: $settings.showDockIcon)
                    .disabled(settings.showDockIcon && !settings.showMenuBarIcon)
                Toggle(L("Show icon in the menu bar"), isOn: $settings.showMenuBarIcon)
                    .disabled(settings.showMenuBarIcon && !settings.showDockIcon)
            } header: {
                Text(L("Icons"))
            } footer: {
                Text(L("At least one stays on, so you can always get back to the window. Click the menu bar icon to show or hide the window, or right-click it for a menu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }
}

// MARK: - Shortcut

struct ShortcutSettingsView: View {
    @Bindable var settings: AppSettings
    private let hotKeys = HotKeyManager.shared

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Quick Chat")) {
                    KeyRecorder(combo: $settings.quickChatHotKey)
                }
                if let error = hotKeys.errors[.quickChat] {
                    ErrorLabel(error: error)
                }
                if settings.quickChatHotKey != .defaultSummon {
                    Button(L("Restore Default (\(KeyCombo.defaultSummon.displayString))")) { settings.quickChatHotKey = .defaultSummon }
                }
                Picker(L("Opens To"), selection: $settings.quickChatOpening) {
                    ForEach(QuickChatOpening.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text(L("Quick Chat"))
            } footer: {
                Text(L("Opens a small input bar over any app. Press ↩ to ask, and the answer appears in a compact window that stays on top. Press the shortcut again to hide it. With Last Conversation, the shortcut reopens the conversation you left, and the window's New Chat button starts a new one."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L("Show or Hide Main Window")) {
                    KeyRecorder(combo: $settings.mainWindowHotKey)
                }
                if let error = hotKeys.errors[.mainWindow] {
                    ErrorLabel(error: error)
                }
                Picker(L("Window Position"), selection: $settings.summonPosition) {
                    ForEach(SummonPosition.allCases) { Text($0.title).tag($0) }
                }
                Toggle(L("Put the cursor in the message box"), isOn: $settings.focusInputOnSummon)
                Toggle(L("Hide when switching to another app"), isOn: $settings.hideOnDeactivate)
            } header: {
                Text(L("Main Window"))
            } footer: {
                Text(L("The main window also opens from the Dock or the menu bar icon. With auto-hide on, float the window on top before dragging files in from Finder, or paste them or use the upload button instead."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("In-App Shortcuts")) {
                ShortcutRow(title: L("New Chat"), keys: "⌘ N")
                ShortcutRow(title: L("Reload Page"), keys: "⌘ R")
                ShortcutRow(title: L("Float on Top"), keys: "⌥ ⌘ T")
                ShortcutRow(title: L("Zoom In / Zoom Out / Actual Size"), keys: "⌘ +  ⌘ −  ⌘ 0")
                ShortcutRow(title: L("Back / Forward"), keys: "⌘ [  ⌘ ]")
                ShortcutRow(title: L("Close Window (keeps running)"), keys: "⌘ W")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ErrorLabel: View {
    let error: HotKeyManager.RegistrationError

    var body: some View {
        Label(error.message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
    }
}

private struct ShortcutRow: View {
    let title: String
    let keys: String

    var body: some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Accounts

struct AccountSettingsView: View {
    let model: WebViewModel
    let profiles: ProfileStore

    @State private var isConfirmingSignOut = false
    @State private var pendingDeletion: Profile?

    var body: some View {
        Form {
            Section {
                ForEach(profiles.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isCurrent: profile.id == profiles.currentID,
                        canDelete: profile.id != profiles.currentID && profiles.profiles.count > 1,
                        onRename: { profiles.rename(profile.id, to: $0) },
                        onSelect: { model.switchProfile(to: profile.id) },
                        onDelete: { pendingDeletion = profile }
                    )
                }
                Button {
                    model.addProfileAndSwitch()
                } label: {
                    Label(L("Add Account"), systemImage: "plus")
                }
            } header: {
                Text(L("Accounts"))
            } footer: {
                Text(L("Each account has its own cookies and local storage, so several DeepSeek accounts can stay signed in and you can switch between them at any time."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Current Account: \(profiles.current.displayName)")) {
                LabeledContent {
                    Button(L("Clear Cache")) { Task { await model.clearCache() } }
                } label: {
                    Text(L("Clear Cache"))
                    Text(L("Use this if the page looks wrong. You stay signed in."))
                }
                LabeledContent {
                    Button(L("Sign Out…"), role: .destructive) { isConfirmingSignOut = true }
                } label: {
                    Text(L("Sign Out and Clear Data"))
                    Text(L("Deletes this account's cookies, local storage and cache on this Mac."))
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L("Sign out of “\(profiles.current.displayName)”?"), isPresented: $isConfirmingSignOut) {
            Button(L("Sign Out and Clear"), role: .destructive) { Task { await model.signOutAndClearData() } }
        } message: {
            Text(L("Your chats stay in the cloud and come back when you sign in again."))
        }
        .confirmationDialog(
            L("Delete the account “\(pendingDeletion?.displayName ?? "")”?"),
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { profile in
            Button(L("Delete"), role: .destructive) { Task { await profiles.remove(profile.id) } }
        } message: { _ in
            Text(L("Its sign-in and website data on this Mac will be permanently deleted."))
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let isCurrent: Bool
    let canDelete: Bool
    let onRename: (String) -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var name = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "person.crop.circle")
                .font(.title3)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            TextField("", text: $name, prompt: Text(L("Account Name")))
                .labelsHidden()
                .textFieldStyle(.plain)
                .help(L("Click to rename"))
                .focused($isEditing)
                .onSubmit { if name != profile.displayName { onRename(name) } }
            Spacer()
            if isCurrent {
                Text(L("In Use"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(L("Switch"), action: onSelect)
            }
            Menu {
                Button(L("Delete Account…"), role: .destructive, action: onDelete)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        // Compared with the display name so the untouched default account keeps following the language.
        .onAppear { name = profile.displayName }
        .onChange(of: profile.displayName) { _, newValue in name = newValue }
        .onChange(of: isEditing) { _, editing in
            if !editing, name != profile.displayName { onRename(name) }
        }
    }
}

// MARK: - Web

struct WebSettingsView: View {
    let model: WebViewModel
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section(L("Page")) {
                LabeledContent(L("Page Zoom")) {
                    HStack(spacing: 8) {
                        Text("\(Int((settings.pageZoom * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(minWidth: 44, alignment: .trailing)
                        Stepper(
                            L("Page Zoom"),
                            value: Binding(get: { settings.pageZoom }, set: { settings.setPageZoom($0) }),
                            in: AppSettings.zoomRange,
                            step: 0.1
                        )
                        .labelsHidden()
                        Button(L("Reset")) { settings.setPageZoom(1.0) }
                            .disabled(settings.pageZoom == 1.0)
                    }
                }
            }

            Section {
                Toggle(L("Open external links in the default browser"), isOn: $settings.openExternalLinksInBrowser)
            } header: {
                Text(L("Links"))
            } footer: {
                Text(L("When off, external links open in a new window in the app. ⌘-clicking a link always uses the default browser."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Downloads")) {
                Toggle(L("Ask where to save each download"), isOn: $settings.askDownloadLocation)
                LabeledContent(L("Default Location")) {
                    Button(L("Show Downloads in Finder")) {
                        NSWorkspace.shared.open(DownloadManager.downloadsDirectory)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return L("Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("DeepSeek")
                .font(.title.weight(.semibold))
            Text(version)
                .foregroundStyle(.secondary)
            Text(L("A native macOS client for DeepSeek's official web app.\nRendered by the system's WebKit. No API key, no private APIs, no data collection."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Link("chat.deepseek.com", destination: LinkPolicy.homeURL)
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
