<p align="center">
  <img src="DeepSeekNative/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" height="128" alt="DeepSeek Native icon">
</p>

<h1 align="center">DeepSeek Native</h1>

<p align="center">
  A lightweight native macOS client for DeepSeek. Ask from any app with <b>⌥ Space</b>. 1.4 MB download, no Electron.
</p>

<p align="center">
  <a href="https://github.com/Lysand-Shen/deepseek-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/Lysand-Shen/deepseek-desktop?label=download&color=4D6BFE" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Lysand-Shen/deepseek-desktop" alt="MIT license"></a>
</p>

<p align="center"><a href="README.md">中文</a> · English</p>

---

DeepSeek Native wraps the official web app, [chat.deepseek.com](https://chat.deepseek.com), in a SwiftUI + AppKit shell using the system's WKWebView. Chat, DeepThink, web search and file uploads work exactly as they do on the web. On top of that it adds what a browser tab can't: a quick chat bar like the ChatGPT and Claude desktop apps, a menu bar icon, multiple accounts, float on top, keeping running after the window closes, and an English or Chinese interface you can switch at any time.

- **Light:** Apple frameworks only, no third-party dependencies. The app is 3.4 MB and the DMG about 1.4 MB, universal for Apple Silicon and Intel.
- **Fast:** about 0.8 s from launch to chatting on later launches. The page is created once, so showing and hiding are instant.
- **No API key:** it doesn't use the DeepSeek API or any undocumented endpoint. You sign in with your normal DeepSeek account.

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

**Quick chat (⌥ Space)**
- Press **⌥ Space** in any app and a pill-shaped input bar appears in the lower part of the screen, without switching away from the app you're in.
- Type a question and press ↩. Like Gemini's, the bar grows upwards into a compact window that stays on top: the answer appears above, and DeepSeek's message box sits where the bar was, ready for follow-ups. ⌥↩ adds a line and ⎋ closes.
- Floating buttons at the top close the window, start a new chat (shrinking back into the bar), or open the conversation in the main window. Drag the top of the window to move it.
- Press the shortcut again to hide it.
- Quick chat uses a page of its own, so it never interrupts a conversation in the main window. Its chats are saved in your DeepSeek history like any other.
- Record a different shortcut, or turn it off, in Settings › Shortcut.

**Main window shortcut**
- Optionally set a second global shortcut that shows or hides the full main window. It's off by default.
- Summon to the window's last position or to the center of the screen with the pointer. The window follows you to the current Space.
- The message box gets focus on summon. Optionally hide when you switch to another app.
- Global shortcuts use Carbon `RegisterEventHotKey`, so they need no Accessibility permission.

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
- English and Simplified Chinese interface. It follows the system by default, or pick one in Settings › General › Language. Menus, Settings and dialogs switch right away; menu items provided by macOS and the default language of DeepSeek's page switch after a restart.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌥ Space | Quick chat: show or hide the input bar (global, customizable) |
| Your choice | Show or hide the main window (global, off by default) |
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
Another app probably uses the same shortcut, for example Alfred, Raycast, ChatGPT or Claude's Quick Entry. Then only one app may respond, or both may. Pick a different shortcut in Settings › Shortcut, or change the other app's.

**How does quick chat send my question?**
The same way you would: the compact window opens DeepSeek's web page, types your question into the page's message box and presses Return. No API and no undocumented endpoints. DeepThink and Search stay as you last set them on the page.

**How do I switch the interface to Chinese (or English)?**
Open Settings › General › Language. With System, the interface is Chinese when your Mac's preferred language is Chinese, and English otherwise.

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

Interface text lives in the String Catalog `DeepSeekNative/Resources/Localizable.xcstrings`, with English as the source language and a Simplified Chinese translation. Code looks strings up with `L("…")`, which refreshes the interface when the language changes. To add a language, add it to that file in Xcode, then add its code to `AppLanguage` in `Localizer.swift` and to `CFBundleLocalizations` in `Info.plist`.

### Layout

```
DeepSeekNative/
  App/          main.swift, AppDelegate (lifecycle, menu actions, summoning), MainMenu
  Settings/     AppSettings (UserDefaults), ProfileStore (accounts), LaunchAtLogin,
                Localizer (interface language, switched at runtime)
  HotKey/       KeyCombo, HotKeyManager (Carbon global hotkeys)
  QuickChat/    QuickChatController, QuickEntryPanel (input bar), QuickChatPanel (compact window),
                QuickChatSession (the compact window's own page)
  Web/          WebViewModel (WKWebView and its state), WebViewDelegate, LinkPolicy,
                DownloadManager, WebDialogs, NetworkMonitor, WebScripts
  Window/       MainWindowController (window and toolbar), PopupWindowController, StatusItemController
  Views/        MainContentView (web view with loading, error and offline states), Settings/*
```

State lives in `@MainActor @Observable` classes, built with Swift 6 strict concurrency and no warnings. AppKit manages the windows, menus and status item; SwiftUI draws the content and settings.

## Known limitations

- The app is ad-hoc signed and not notarized, so it has to be allowed once on first launch (see Install).
- App Sandbox is off, because with ad-hoc signing every rebuild would trigger sandbox container prompts. Hardened Runtime is on, and web content runs in WebKit's own sandboxed processes.
- The toolbar's New Chat button clicks the page's own "New chat" control and falls back to reloading the home page.
- Quick chat types the question into the page's message box and presses Return. If a DeepSeek redesign breaks that, the question stays in the compact window's message box to send by hand, and `WebScripts.swift` needs updating.
- After quick chat has been hidden for 10 minutes, its page is released to save memory, so the next question takes a second or two longer.
- The quick chat window hides the header of DeepSeek's narrow layout, found by its class name `the-header`. If DeepSeek renames it, the header shows again and everything else keeps working.

## Disclaimer

This is an unofficial third-party client. It is not affiliated with or endorsed by Hangzhou DeepSeek Artificial Intelligence Co., Ltd. The DeepSeek name and whale logo belong to their owner and are used only to identify the service the app loads; they are not covered by this project's MIT license. The chat service is provided by DeepSeek under its own terms of use.

## License

The code is released under the [MIT](LICENSE) license.
