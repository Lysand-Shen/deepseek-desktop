import AppKit
import SwiftUI

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    private let launchAtLogin = LaunchAtLogin.shared

    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时自动打开", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text("需要在“系统设置 › 通用 › 登录项”中允许 DeepSeek。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开系统设置") { launchAtLogin.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
                if let error = launchAtLogin.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("启动时不显示窗口（仅在后台运行）", isOn: $settings.startHidden)
                    .disabled(!settings.keepRunningInBackground)
            }

            Section("窗口") {
                Picker("外观", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("窗口置顶", isOn: $settings.floatOnTop)
                Toggle("关闭窗口后继续在后台运行", isOn: $settings.keepRunningInBackground)
            }

            Section {
                Toggle("在程序坞中显示图标", isOn: $settings.showDockIcon)
                    .disabled(settings.showDockIcon && !settings.showMenuBarIcon)
                Toggle("在菜单栏中显示图标", isOn: $settings.showMenuBarIcon)
                    .disabled(settings.showMenuBarIcon && !settings.showDockIcon)
            } header: {
                Text("图标")
            } footer: {
                Text("两者至少保留一个，方便随时找回窗口。点按菜单栏图标可显示或隐藏窗口，右键点按打开菜单。")
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
                LabeledContent("显示 / 隐藏 DeepSeek") {
                    KeyRecorder(combo: $settings.hotKey)
                }
                if let error = hotKeys.registrationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if settings.hotKey != .defaultSummon {
                    Button("恢复默认（⌥ Space）") { settings.hotKey = .defaultSummon }
                }
            } header: {
                Text("全局快捷键")
            } footer: {
                Text("在任何应用中按下即可唤出 DeepSeek，再按一次隐藏并回到之前的应用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("窗口位置", selection: $settings.summonPosition) {
                    ForEach(SummonPosition.allCases) { Text($0.title).tag($0) }
                }
                Toggle("唤出后自动聚焦输入框", isOn: $settings.focusInputOnSummon)
                Toggle("切换到其他应用时自动隐藏", isOn: $settings.hideOnDeactivate)
            } header: {
                Text("唤出时")
            } footer: {
                Text("开启“自动隐藏”后，从访达拖拽文件到窗口前需要先固定窗口，可改用粘贴或上传按钮。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("应用内快捷键") {
                ShortcutRow(title: "新对话", keys: "⌘ N")
                ShortcutRow(title: "重新载入页面", keys: "⌘ R")
                ShortcutRow(title: "窗口置顶", keys: "⌥ ⌘ T")
                ShortcutRow(title: "放大 / 缩小 / 实际大小", keys: "⌘ +  ⌘ −  ⌘ 0")
                ShortcutRow(title: "后退 / 前进", keys: "⌘ [  ⌘ ]")
                ShortcutRow(title: "关闭窗口（后台继续运行）", keys: "⌘ W")
            }
        }
        .formStyle(.grouped)
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
                    Label("添加账户", systemImage: "plus")
                }
            } header: {
                Text("账户")
            } footer: {
                Text("每个账户拥有独立的 Cookie 与本地存储，可同时保持多个 DeepSeek 账号的登录状态并随时切换。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("当前账户：\(profiles.current.name)") {
                LabeledContent {
                    Button("清除缓存") { Task { await model.clearCache() } }
                } label: {
                    Text("清除缓存")
                    Text("页面显示异常时使用，登录状态会保留。")
                }
                LabeledContent {
                    Button("退出登录…", role: .destructive) { isConfirmingSignOut = true }
                } label: {
                    Text("退出登录并清除数据")
                    Text("删除该账户在本机的 Cookie、本地存储与缓存。")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("退出“\(profiles.current.name)”？", isPresented: $isConfirmingSignOut) {
            Button("退出并清除", role: .destructive) { Task { await model.signOutAndClearData() } }
        } message: {
            Text("云端聊天记录不受影响，重新登录后即可看到。")
        }
        .confirmationDialog(
            "删除账户“\(pendingDeletion?.name ?? "")”？",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { profile in
            Button("删除", role: .destructive) { Task { await profiles.remove(profile.id) } }
        } message: { _ in
            Text("该账户在本机的登录状态与网站数据将被永久删除。")
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
            TextField("", text: $name, prompt: Text("账户名称"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .help("点按以重命名")
                .focused($isEditing)
                .onSubmit { onRename(name) }
            Spacer()
            if isCurrent {
                Text("使用中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("切换", action: onSelect)
            }
            Menu {
                Button("删除账户…", role: .destructive, action: onDelete)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .onAppear { name = profile.name }
        .onChange(of: profile.name) { _, newValue in name = newValue }
        .onChange(of: isEditing) { _, editing in
            if !editing, name != profile.name { onRename(name) }
        }
    }
}

// MARK: - Web

struct WebSettingsView: View {
    let model: WebViewModel
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("页面") {
                LabeledContent("页面缩放") {
                    HStack(spacing: 8) {
                        Text("\(Int((settings.pageZoom * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(minWidth: 44, alignment: .trailing)
                        Stepper(
                            "页面缩放",
                            value: Binding(get: { settings.pageZoom }, set: { settings.setPageZoom($0) }),
                            in: AppSettings.zoomRange,
                            step: 0.1
                        )
                        .labelsHidden()
                        Button("重置") { settings.setPageZoom(1.0) }
                            .disabled(settings.pageZoom == 1.0)
                    }
                }
            }

            Section {
                Toggle("在默认浏览器中打开外部链接", isOn: $settings.openExternalLinksInBrowser)
            } header: {
                Text("链接")
            } footer: {
                Text("关闭后，外部链接会在应用内的新窗口中打开。按住 ⌘ 点按链接总会使用默认浏览器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("下载") {
                Toggle("每次下载前询问保存位置", isOn: $settings.askDownloadLocation)
                LabeledContent("默认位置") {
                    Button("在访达中打开“下载”") {
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
        return "版本 \(short)（\(build)）"
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
            Text("基于 DeepSeek 官方网页版的原生 macOS 客户端。\n使用系统 WebKit 渲染，无需 API Key，不调用任何私有接口，不收集数据。")
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
