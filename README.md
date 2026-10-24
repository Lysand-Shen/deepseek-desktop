# DeepSeek Native

轻量的 macOS 原生 DeepSeek 客户端。用 SwiftUI + AppKit 搭外壳，用系统 WKWebView 加载 [chat.deepseek.com](https://chat.deepseek.com)，在官方网页版之上补齐全局快捷键、菜单栏、多账户等原生体验。

- 不使用 DeepSeek API，不需要 API Key，不调用任何未公开接口
- 没有 Electron / Chromium，也没有第三方依赖，只用 Apple 自带框架
- 安装包约 2.7 MB（通用二进制，同时支持 Apple Silicon 与 Intel）

## 功能

**网页版完整体验**
- 登录、聊天、历史会话、深度思考、联网搜索、附件上传等功能都由官方网页提供
- Cookie 与本地存储持久保留，重启后保持登录
- 原生文件选择面板（上传）、下载到“下载”文件夹（可改为每次询问）、JS 弹窗
- 外部链接默认用系统浏览器打开；Google / Apple / 微信登录弹窗留在应用内完成
- 加载进度条、错误页、断网提示，网络恢复后自动重新加载；网页进程崩溃后自动恢复

**原生窗口**
- 工具栏颜色跟随网页背景（浅色、深色都适配），标题显示当前会话名
- 自动记住窗口大小和位置；窗口切换到另一块显示器时会自动移回屏幕可见范围内
- 窗口置顶（⌥⌘T 或工具栏图钉）
- 关闭窗口后可在后台继续运行，正在生成的回复不会中断
- 外观可选：跟随系统 / 浅色 / 深色

**全局快捷键**
- 默认 **⌥ Space**：在任何应用中唤出，再按一次隐藏并回到之前的应用
- 可在“设置 › 快捷键”中录制新的组合；按 ⌫ 停用，按 ⎋ 取消录制
- 唤出位置可选“保持上次位置”或“鼠标所在屏幕居中”；窗口会跟到当前桌面空间（Space），不会切走
- 唤出后自动聚焦输入框；可选“切换到其他应用时自动隐藏”
- 基于 Carbon `RegisterEventHotKey`，不需要辅助功能权限

**其他**
- 菜单栏图标：点按切换窗口，右键点按打开菜单
- 多账户：每个账户使用独立的 `WKWebsiteDataStore`，可同时保持多个账号的登录状态并随时切换
- 页面缩放（⌘+ / ⌘− / ⌘0）、后退前进（⌘[ / ⌘]）、清除缓存、退出并清除数据
- 登录时自动启动（`SMAppService`）、可隐藏程序坞图标

## 构建

需要 Xcode 16 或更高版本（Swift 6），运行系统为 macOS 14 或更高版本。

```bash
scripts/build.sh            # Release 构建，产物在 dist/DeepSeek.app
scripts/build.sh --install  # 构建并安装到 /Applications
scripts/build.sh --dmg      # 额外生成 dist/DeepSeek.dmg
```

工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 根据 `project.yml` 生成，生成好的 `DeepSeekNative.xcodeproj` 也一并提交，没装 XcodeGen 也能直接用 Xcode 打开。修改图标后运行 `swift scripts/make-icons.swift DeepSeekNative/Resources/Assets.xcassets` 重新生成。

> 构建产物（DerivedData）放在 `~/Library/Developer/Xcode/DerivedData/DeepSeekNative`。如果项目位于 iCloud 同步的“文稿”文件夹，系统会给 .app 加上 Finder 元数据，直接在项目目录内签名会失败，所以构建放在了同步目录之外。

## 代码结构

```
DeepSeekNative/
  App/          main.swift、AppDelegate（生命周期、菜单动作、唤出逻辑）、MainMenu
  Settings/     AppSettings（UserDefaults 持久化）、ProfileStore（多账户）、LaunchAtLogin
  HotKey/       KeyCombo、HotKeyManager（Carbon 全局快捷键）
  Web/          WebViewModel（WKWebView 与状态）、WebViewDelegate、LinkPolicy（链接分流）、
                DownloadManager、WebDialogs、NetworkMonitor、WebScripts
  Window/       MainWindowController（窗口与工具栏）、PopupWindowController、StatusItemController
  Views/        MainContentView（网页与加载/错误/断网/提示层）、Settings/*
```

- 状态类均为 `@MainActor @Observable`，开启 Swift 6 严格并发检查，编译零警告
- 窗口、菜单、菜单栏图标用 AppKit 管理（窗口需要隐藏、唤出、跨桌面空间移动），内容和设置页用 SwiftUI
- WKWebView 只创建一次；关闭窗口只是隐藏，不会销毁页面

## 已知限制

- **⌥ Space 可能与其他应用冲突**：Claude 桌面版的 Quick Entry、ChatGPT 桌面版等也默认使用 ⌥ Space。冲突时请在任一方修改快捷键
- 应用使用 ad-hoc 签名，App Sandbox 未开启（ad-hoc 签名下每次重新构建都会触发沙盒容器的权限提示）。启用了 Hardened Runtime，网页内容运行在 WebKit 自己的沙盒进程中。复制到其他 Mac 首次打开时需要右键点按并选择“打开”
- “新对话”按钮会点击网页自带的“开启新对话”按钮，找不到时退回为重新载入首页
- 第三方登录（例如 Google）是否允许在内嵌浏览器中使用，由对方决定；应用使用 Safari 的 User-Agent 以提高兼容性

## 调试

```bash
defaults write com.sink7.DeepSeekNative WebInspectorEnabled -bool true   # Release 版开启 Safari 网页检查器
log stream --level info --predicate 'subsystem == "com.sink7.DeepSeekNative"'
```
