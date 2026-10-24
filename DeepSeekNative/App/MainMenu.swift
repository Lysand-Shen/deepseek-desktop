import AppKit

/// Builds the menu bar. App-specific items target the `AppDelegate`; standard editing and
/// window items go up the responder chain so WKWebView handles copy, paste and undo.
@MainActor
enum MainMenuBuilder {
    static func build(for app: AppDelegate, accountMenu: NSMenu) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu(appMenu(app)))
        mainMenu.addItem(submenu(fileMenu(app)))
        mainMenu.addItem(submenu(editMenu()))
        mainMenu.addItem(submenu(viewMenu(app)))
        accountMenu.delegate = app
        mainMenu.addItem(submenu(accountMenu))
        let windowMenu = windowMenu(app)
        mainMenu.addItem(submenu(windowMenu))
        let helpMenu = helpMenu(app)
        mainMenu.addItem(submenu(helpMenu))
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
        return mainMenu
    }

    private static func appMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "DeepSeek")
        menu.addItem(item("关于 DeepSeek", #selector(AppDelegate.showAbout(_:)), target: app))
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(AppDelegate.showSettings(_:)), ",", target: app))
        menu.addItem(.separator())
        let services = NSMenu(title: "服务")
        NSApp.servicesMenu = services
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(item("隐藏 DeepSeek", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("隐藏其他", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("全部显示", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("退出 DeepSeek", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "文件")
        menu.addItem(item("新对话", #selector(AppDelegate.newChat(_:)), "n", target: app))
        menu.addItem(.separator())
        menu.addItem(item("关闭窗口", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(item("撤销", Selector(("undo:")), "z"))
        menu.addItem(item("重做", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("剪切", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("拷贝", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("粘贴", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("粘贴并匹配样式", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("删除", #selector(NSText.delete(_:))))
        menu.addItem(item("全选", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func viewMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "显示")
        menu.addItem(item("重新载入页面", #selector(AppDelegate.reloadPage(_:)), "r", target: app))
        menu.addItem(item("强制重新载入", #selector(AppDelegate.reloadIgnoringCache(_:)), "r", [.command, .shift], target: app))
        menu.addItem(.separator())
        menu.addItem(item("实际大小", #selector(AppDelegate.actualSize(_:)), "0", target: app))
        menu.addItem(item("放大", #selector(AppDelegate.zoomIn(_:)), "+", target: app))
        // ⌘= is what people actually press for "zoom in" on most layouts.
        let zoomInAlias = item("放大", #selector(AppDelegate.zoomIn(_:)), "=", target: app)
        zoomInAlias.isHidden = true
        zoomInAlias.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlias)
        menu.addItem(item("缩小", #selector(AppDelegate.zoomOut(_:)), "-", target: app))
        menu.addItem(.separator())
        menu.addItem(item("后退", #selector(AppDelegate.goBack(_:)), "[", target: app))
        menu.addItem(item("前进", #selector(AppDelegate.goForward(_:)), "]", target: app))
        menu.addItem(.separator())
        menu.addItem(item("进入全屏幕", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "窗口")
        menu.addItem(item("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("缩放", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("窗口置顶", #selector(AppDelegate.toggleFloatOnTop(_:)), "t", [.command, .option], target: app))
        menu.addItem(item("DeepSeek 主窗口", #selector(AppDelegate.showMainWindow(_:)), "1", target: app))
        menu.addItem(.separator())
        menu.addItem(item("前置全部窗口", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "帮助")
        menu.addItem(item("在浏览器中打开当前页面", #selector(AppDelegate.openCurrentPageInBrowser(_:)), target: app))
        menu.addItem(item("DeepSeek 官网", #selector(AppDelegate.openDeepSeekWebsite(_:)), target: app))
        return menu
    }

    // MARK: Helpers

    static func item(
        _ title: String, _ action: Selector?, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        item.target = target
        return item
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
