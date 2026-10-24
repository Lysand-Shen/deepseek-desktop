<p align="center">
  <img src="DeepSeekNative/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="DeepSeek Native 图标">
</p>

<h1 align="center">DeepSeek Native</h1>

<p align="center">
  轻量的 macOS 原生 DeepSeek 客户端：按 <b>⌥ Space</b> 随时唤出，下载只有 1.2 MB，没有 Electron。
</p>

<p align="center">
  <a href="https://github.com/Lysand-Shen/deepseek-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/Lysand-Shen/deepseek-desktop?label=%E4%B8%8B%E8%BD%BD&color=4D6BFE" alt="下载"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Lysand-Shen/deepseek-desktop" alt="MIT 许可"></a>
</p>

<p align="center">中文 · <a href="README.en.md">English</a></p>

---

DeepSeek Native 用 SwiftUI + AppKit 搭外壳，用系统自带的 WKWebView 加载官方网页版 [chat.deepseek.com](https://chat.deepseek.com)。聊天、深度思考、联网搜索、上传文件等功能都和网页版完全一致，在此之上补齐了网页做不到的原生体验：全局快捷键、菜单栏图标、多账户、窗口置顶、关闭后在后台继续运行。

- **轻**：只用 Apple 自带框架，没有第三方依赖。应用 2.6 MB，DMG 约 1.2 MB；同时支持 Apple Silicon 和 Intel
- **快**：再次启动时约 0.8 秒就能开始聊天；网页只创建一次，唤出和隐藏是瞬间的
- **省心**：不需要 API Key，不使用 DeepSeek API，也不调用任何未公开接口；用的就是你在浏览器里登录的那个账号

## 下载安装

1. 到 [Releases](https://github.com/Lysand-Shen/deepseek-desktop/releases/latest) 下载 `DeepSeek-x.y.z.dmg`
2. 打开 DMG，把 **DeepSeek** 拖进“应用程序”文件夹
3. 第一次打开时，macOS 会提示“无法验证开发者”。这是因为应用没有经过 Apple 公证（需要付费的开发者账号），任选一种方式放行：
   - 打开“系统设置 › 隐私与安全性”，在页面下方找到 DeepSeek，点按“仍要打开”
   - 或者在终端运行：

     ```bash
     xattr -dr com.apple.quarantine /Applications/DeepSeek.app
     ```

需要 macOS 14 Sonoma 或更高版本。

## 功能

**网页版的完整体验**
- 登录、聊天、历史会话、深度思考、联网搜索、上传图片和文件，都由官方网页提供
- 登录状态和本地存储持久保留，重启后不用重新登录
- 原生文件选择面板；下载默认保存到“下载”文件夹（可改为每次询问）
- 外部链接默认用系统浏览器打开；Google、Apple、微信等第三方登录在应用内的弹窗中完成
- 加载进度条、错误页、断网提示；网络恢复后自动重新加载，网页进程崩溃后自动恢复

**全局快捷键**
- 默认 **⌥ Space**：在任何应用中唤出，再按一次隐藏并回到之前的应用
- 可以在“设置 › 快捷键”中录制新的组合，或者停用
- 唤出位置可选“保持上次位置”或“鼠标所在屏幕居中”；窗口会跟到当前桌面空间，不会切走
- 唤出后自动聚焦输入框；可选“切换到其他应用时自动隐藏”
- 基于 Carbon `RegisterEventHotKey` 实现，不需要辅助功能权限

**原生窗口**
- 工具栏颜色跟随网页背景，浅色、深色模式都无缝衔接；标题栏显示当前会话名
- 记住窗口大小和位置；窗口跑到屏幕外时会自动移回来
- 窗口置顶、全屏、页面缩放
- 关闭窗口后可在后台继续运行，正在生成的回复不会中断
- 外观可选：跟随系统、浅色、深色

**其他**
- 菜单栏图标：点按显示或隐藏窗口，右键点按打开菜单
- 多账户：每个账户使用独立的数据存储，可以同时保持多个账号登录并随时切换
- 登录时自动启动，可隐藏程序坞图标
- 菜单和设置均为中文

## 键盘快捷键

| 快捷键 | 功能 |
| --- | --- |
| ⌥ Space | 唤出或隐藏窗口（全局，可自定义） |
| ⌘ N | 新对话 |
| ⌘ R / ⇧ ⌘ R | 重新载入 / 强制重新载入 |
| ⌘ + / ⌘ − / ⌘ 0 | 放大 / 缩小 / 实际大小 |
| ⌘ [ / ⌘ ] | 后退 / 前进 |
| ⌥ ⌘ T | 窗口置顶 |
| ⌃ ⌘ F | 进入全屏幕 |
| ⌘ 1 | 显示主窗口 |
| ⌘ , | 设置 |
| ⌘ W | 关闭窗口（应用继续在后台运行） |

## 常见问题

**按 ⌥ Space 没有反应？**
很可能有其他应用也用了这个组合，例如 Alfred、Raycast、ChatGPT 桌面版、Claude 桌面版的快速输入。这时可能只有一个应用响应，也可能两个同时响应。请在“设置 › 快捷键”里换一个组合，或者修改另一个应用的快捷键。

**我的数据存在哪里？会被上传吗？**
所有登录信息和网页数据都由 WebKit 保存在本机 `~/Library/WebKit/com.sink7.DeepSeekNative`。应用本身不收集任何信息，除了 WebKit 加载 DeepSeek 网页，不会发出其他网络请求。代码完全开源，可以自行检查。

**Google 登录失败？**
是否允许在内嵌浏览器中登录由 Google 决定。应用已使用 Safari 的 User-Agent 以提高兼容性，如果仍被拒绝，可以改用手机号、邮箱或微信登录。

**如何彻底卸载？**
退出应用后删除 `/Applications/DeepSeek.app`，再删除数据和设置：

```bash
rm -rf ~/Library/WebKit/com.sink7.DeepSeekNative ~/Library/Preferences/com.sink7.DeepSeekNative.plist
```

## 从源码构建

需要 Xcode 16 或更高版本（Swift 6）。

```bash
git clone https://github.com/Lysand-Shen/deepseek-desktop.git
cd deepseek-desktop
scripts/build.sh            # Release 构建，产物在 dist/DeepSeek.app
scripts/build.sh --install  # 构建并安装到 /Applications
scripts/build.sh --dmg      # 额外生成 dist/DeepSeek-<版本号>.dmg
```

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 根据 `project.yml` 生成。生成好的 `DeepSeekNative.xcodeproj` 也一并提交了，没装 XcodeGen 也能直接用 Xcode 打开。

应用图标由 `scripts/make-icons.swift` 根据 DeepSeek 官方标志 `scripts/deepseek-logo.svg` 生成：

```bash
swift scripts/make-icons.swift DeepSeekNative/Resources/Assets.xcassets
```

> 构建产物放在 `~/Library/Developer/Xcode/DerivedData/DeepSeekNative`。如果项目位于 iCloud 同步的“文稿”文件夹，系统会给 .app 加上 Finder 元数据，直接在项目目录内签名会失败，所以构建放在了同步目录之外。

### 代码结构

```
DeepSeekNative/
  App/          main.swift、AppDelegate（生命周期、菜单动作、唤出逻辑）、MainMenu
  Settings/     AppSettings（UserDefaults 持久化）、ProfileStore（多账户）、LaunchAtLogin
  HotKey/       KeyCombo、HotKeyManager（Carbon 全局快捷键）
  Web/          WebViewModel（WKWebView 与状态）、WebViewDelegate、LinkPolicy（链接分流）、
                DownloadManager、WebDialogs、NetworkMonitor、WebScripts
  Window/       MainWindowController（窗口与工具栏）、PopupWindowController、StatusItemController
  Views/        MainContentView（网页与加载、错误、断网提示）、Settings/*
```

- 状态类均为 `@MainActor @Observable`，开启 Swift 6 严格并发检查，编译零警告
- 窗口、菜单、菜单栏图标用 AppKit 管理（窗口需要隐藏、唤出、跨桌面空间移动），内容和设置页用 SwiftUI
- WKWebView 只创建一次；关闭窗口只是隐藏，不会销毁页面

### 调试

```bash
defaults write com.sink7.DeepSeekNative WebInspectorEnabled -bool true   # Release 版开启 Safari 网页检查器
log stream --level info --predicate 'subsystem == "com.sink7.DeepSeekNative"'
```

## 已知限制

- 应用使用 ad-hoc 签名，没有经过 Apple 公证，第一次打开需要手动放行（见“下载安装”）
- 没有开启 App Sandbox：ad-hoc 签名下，每次重新构建都会触发沙盒容器的权限提示。已启用 Hardened Runtime，网页内容运行在 WebKit 自己的沙盒进程中
- 工具栏的“新对话”按钮会点击网页自带的“开启新对话”按钮，找不到时退回为重新载入首页。如果 DeepSeek 改版，可能需要更新 `WebScripts.swift`

## 免责声明

本项目是非官方的第三方客户端，与杭州深度求索人工智能基础技术研究有限公司（DeepSeek）没有关联，也未获得其认可。“DeepSeek”名称和鲸鱼标志归其所有者所有，本项目仅用它们表明应用加载的是哪个服务，它们不在本项目的 MIT 许可范围内。聊天服务由 DeepSeek 提供，使用时请遵守 DeepSeek 的用户协议。

## 许可

代码以 [MIT](LICENSE) 许可开源。
