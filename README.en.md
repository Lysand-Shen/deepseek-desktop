<p align="center">
  <img src="DeepSeekNative/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="DeepSeek Native icon">
</p>

<h1 align="center">DeepSeek Native</h1>

<p align="center">
  A lightweight native macOS client for DeepSeek. Summon it from anywhere with <b>⌥ Space</b>. 1.2 MB download, no Electron.
</p>

<p align="center">
  <a href="https://github.com/Lysand-Shen/deepseek-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/Lysand-Shen/deepseek-desktop?label=download&color=4D6BFE" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Lysand-Shen/deepseek-desktop" alt="MIT license"></a>
</p>

<p align="center"><a href="README.md">中文</a> · English</p>

---

DeepSeek Native wraps the official web app, [chat.deepseek.com](https://chat.deepseek.com), in a SwiftUI + AppKit shell using the system's WKWebView. Chat, DeepThink, web search and file uploads work exactly as they do on the web. On top of that it adds what a browser tab can't: a global hotkey, a menu bar icon, multiple accounts, float on top, and keeping running after the window closes.

- **Light:** Apple frameworks only, no third-party dependencies. The app is 2.6 MB and the DMG about 1.2 MB, universal for Apple Silicon and Intel.
- **Fast:** about 0.8 s from launch to chatting on later launches. The page is created once, so showing and hiding are instant.
- **No API key:** it doesn't use the DeepSeek API or any undocumented endpoint. You sign in with your normal DeepSeek account.

The app's menus and settings are in Simplified Chinese.

## Install

1. Download `DeepSeek-x.y.z.dmg` from [Releases](https://github.com/Lysand-Shen/deepseek-desktop/releases/latest).
2. Open the DMG and drag **DeepSeek** into Applications.
3. The app isn't notarized by Apple (that needs a paid developer account), so macOS blocks it the first time. Allow it either way:
   - Open System Settings › Privacy & Security, scroll down to DeepSeek and click **Open Anyway**.
   - Or run this in Terminal:

     ```bash
     xattr -dr com.apple.quarantine /Applications/DeepSeek.app
     ```

Requires macOS 14 Sonoma or later.

## Features

**The full web app**
- Sign-in, chat history, DeepThink, web search and image and file uploads all come from the official site.
- Cookies and local storage persist, so you stay signed in across restarts.
- Native open panels for uploads. Downloads go to Downloads, or ask each time.
- External links open in your default browser. Google, Apple and WeChat sign-in finish in an in-app popup.
- Progress bar, error page and offline banner. The page reloads when the network comes back and recovers if the web content process crashes.

**Global hotkey**
- **⌥ Space** by default: brings DeepSeek up over any app, and pressing it again hides it and returns to where you were.
- Record a different shortcut, or turn it off, in Settings › 快捷键 (Shortcut).
- Summon to the window's last position or to the center of the screen with the mouse. The window follows you to the current Space.
- The chat input gets focus on summon. Optionally hide when you switch to another app.
- Built on Carbon `RegisterEventHotKey`, so it needs no Accessibility permission.

**Native window**
- The toolbar takes on the page's background color in both light and dark mode, and shows the conversation title.
- Remembers its size and position, and moves back on screen if a display goes away.
- Float on top, full screen, page zoom.
- Closing the window keeps the app running, so a reply that's still generating isn't cut off.
- Appearance: follow the system, light or dark.

**More**
- Menu bar icon: click to show or hide the window, right-click for a menu.
- Multiple accounts, each with its own data store, so several stay signed in and you can switch any time.
- Launch at login, and an option to hide the Dock icon.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌥ Space | Show or hide the window (global, customizable) |
| ⌘ N | New chat |
| ⌘ R / ⇧ ⌘ R | Reload / reload ignoring cache |
| ⌘ + / ⌘ − / ⌘ 0 | Zoom in / zoom out / actual size |
| ⌘ [ / ⌘ ] | Back / forward |
| ⌥ ⌘ T | Float on top |
| ⌃ ⌘ F | Enter full screen |
| ⌘ 1 | Show the main window |
| ⌘ , | Settings |
| ⌘ W | Close the window (the app keeps running) |

## FAQ

**⌥ Space does nothing.**
Another app probably uses the same shortcut, for example Alfred, Raycast, ChatGPT or Claude's Quick Entry. Then only one app may respond, or both may. Pick a different shortcut in Settings › 快捷键, or change the other app's.

**Where is my data, and is any of it sent anywhere?**
WebKit keeps sign-in and site data on your Mac in `~/Library/WebKit/com.sink7.DeepSeekNative`. The app collects nothing and makes no network requests of its own beyond WebKit loading DeepSeek's site. The source is all here to check.

**Google sign-in fails.**
Google decides whether to allow sign-in inside embedded browsers. The app sends Safari's User-Agent to improve compatibility. If Google still refuses, sign in with a phone number, email or WeChat instead.

**How do I uninstall completely?**
Quit the app, delete `/Applications/DeepSeek.app`, then remove its data and settings:

```bash
rm -rf ~/Library/WebKit/com.sink7.DeepSeekNative ~/Library/Preferences/com.sink7.DeepSeekNative.plist
```

## Building from source

Requires Xcode 16 or later (Swift 6).

```bash
git clone https://github.com/Lysand-Shen/deepseek-desktop.git
cd deepseek-desktop
scripts/build.sh            # Release build into dist/DeepSeek.app
scripts/build.sh --install  # …and install it to /Applications
scripts/build.sh --dmg      # …and package dist/DeepSeek-<version>.dmg
```

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen). The generated `DeepSeekNative.xcodeproj` is committed too, so Xcode can open it without XcodeGen installed.

`scripts/make-icons.swift` renders the app icons from DeepSeek's official logo in `scripts/deepseek-logo.svg`:

```bash
swift scripts/make-icons.swift DeepSeekNative/Resources/Assets.xcassets
```

### Layout

```
DeepSeekNative/
  App/          main.swift, AppDelegate (lifecycle, menu actions, summoning), MainMenu
  Settings/     AppSettings (UserDefaults), ProfileStore (accounts), LaunchAtLogin
  HotKey/       KeyCombo, HotKeyManager (Carbon global hotkey)
  Web/          WebViewModel (WKWebView and its state), WebViewDelegate, LinkPolicy,
                DownloadManager, WebDialogs, NetworkMonitor, WebScripts
  Window/       MainWindowController (window and toolbar), PopupWindowController, StatusItemController
  Views/        MainContentView (web view with loading, error and offline states), Settings/*
```

State lives in `@MainActor @Observable` classes, built with Swift 6 strict concurrency and no warnings. AppKit manages the windows, menus and status item; SwiftUI draws the content and settings.

## Known limitations

- The app is ad-hoc signed and not notarized, so it has to be allowed once on first launch (see Install).
- App Sandbox is off, because with ad-hoc signing every rebuild would trigger sandbox container prompts. Hardened Runtime is on, and web content runs in WebKit's own sandboxed processes.
- The toolbar's New Chat button clicks the page's own "New chat" control and falls back to reloading the home page. A DeepSeek redesign may require updating `WebScripts.swift`.

## Disclaimer

This is an unofficial third-party client. It is not affiliated with or endorsed by Hangzhou DeepSeek Artificial Intelligence Co., Ltd. The DeepSeek name and whale logo belong to their owner and are used only to identify the service the app loads; they are not covered by this project's MIT license. The chat service is provided by DeepSeek under its own terms of use.

## License

The code is released under the [MIT](LICENSE) license.
