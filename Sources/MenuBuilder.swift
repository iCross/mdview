// MenuBuilder.swift
// macOS Markdown Viewer - 選單建構元件

import AppKit

class MenuBuilder {
    
    // MARK: - Properties
    
    private weak var appDelegate: AppDelegate?
    
    // MARK: - Initialization
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }
    
    // MARK: - Menu Building
    
    func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        
        // 應用程式選單
        mainMenu.addItem(buildAppMenu())
        
        // 檔案選單
        mainMenu.addItem(buildFileMenu())
        
        // 編輯選單
        mainMenu.addItem(buildEditMenu())
        
        // 檢視選單
        mainMenu.addItem(buildViewMenu())
        
        // 視窗選單
        mainMenu.addItem(buildWindowMenu())
        
        // 說明選單
        mainMenu.addItem(buildHelpMenu())
        
        return mainMenu
    }
    
    // MARK: - App Menu
    
    private func buildAppMenu() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        
        // 關於
        let aboutItem = NSMenuItem(
            title: "關於 Markdown Viewer",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // 服務
        let servicesItem = NSMenuItem(title: "服務", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服務")
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // 隱藏應用程式
        let hideItem = NSMenuItem(
            title: "隱藏 Markdown Viewer",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)
        
        // 隱藏其他
        let hideOthersItem = NSMenuItem(
            title: "隱藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        
        // 顯示全部
        let showAllItem = NSMenuItem(
            title: "顯示全部",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(showAllItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // 結束
        let quitItem = NSMenuItem(
            title: "結束 Markdown Viewer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        return appMenuItem
    }
    
    // MARK: - File Menu
    
    private func buildFileMenu() -> NSMenuItem {
        let fileMenuItem = NSMenuItem(title: "檔案", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "檔案")
        
        // 開啟檔案
        let openItem = NSMenuItem(
            title: "開啟...",
            action: #selector(AppDelegate.openFile),
            keyEquivalent: "o"
        )
        openItem.target = appDelegate
        fileMenu.addItem(openItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        // 重新載入
        let reloadItem = NSMenuItem(
            title: "重新載入",
            action: #selector(AppDelegate.reloadCurrentFile),
            keyEquivalent: "r"
        )
        reloadItem.target = appDelegate
        fileMenu.addItem(reloadItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        // 關閉視窗
        let closeItem = NSMenuItem(
            title: "關閉視窗",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileMenu.addItem(closeItem)
        
        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }
    
    // MARK: - Edit Menu
    
    private func buildEditMenu() -> NSMenuItem {
        let editMenuItem = NSMenuItem(title: "編輯", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "編輯")
        
        // 複製
        let copyItem = NSMenuItem(
            title: "複製",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(copyItem)
        
        // 全選
        let selectAllItem = NSMenuItem(
            title: "全選",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(selectAllItem)
        
        editMenuItem.submenu = editMenu
        return editMenuItem
    }
    
    // MARK: - View Menu
    
    private func buildViewMenu() -> NSMenuItem {
        let viewMenuItem = NSMenuItem(title: "檢視", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "檢視")
        
        // 進入全螢幕
        let fullScreenItem = NSMenuItem(
            title: "進入全螢幕",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)
        
        viewMenu.addItem(NSMenuItem.separator())
        
        // 放大
        let zoomInItem = NSMenuItem(
            title: "放大",
            action: #selector(AppDelegate.zoomIn),
            keyEquivalent: "+"
        )
        zoomInItem.target = appDelegate
        viewMenu.addItem(zoomInItem)
        
        // 縮小
        let zoomOutItem = NSMenuItem(
            title: "縮小",
            action: #selector(AppDelegate.zoomOut),
            keyEquivalent: "-"
        )
        zoomOutItem.target = appDelegate
        viewMenu.addItem(zoomOutItem)
        
        // 實際大小
        let actualSizeItem = NSMenuItem(
            title: "實際大小",
            action: #selector(AppDelegate.resetZoom),
            keyEquivalent: "0"
        )
        actualSizeItem.target = appDelegate
        viewMenu.addItem(actualSizeItem)
        
        viewMenu.addItem(NSMenuItem.separator())

        // 主題（Theme）
        let themeItem = NSMenuItem(title: "主題", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "主題")
        
        let themeSystem = NSMenuItem(title: "跟隨系統", action: #selector(AppDelegate.setThemeSystem), keyEquivalent: "")
        themeSystem.target = appDelegate
        themeMenu.addItem(themeSystem)
        
        let themeLight = NSMenuItem(title: "淺色", action: #selector(AppDelegate.setThemeLight), keyEquivalent: "")
        themeLight.target = appDelegate
        themeMenu.addItem(themeLight)
        
        let themeDark = NSMenuItem(title: "深色", action: #selector(AppDelegate.setThemeDark), keyEquivalent: "")
        themeDark.target = appDelegate
        themeMenu.addItem(themeDark)
        
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)
        
        viewMenu.addItem(NSMenuItem.separator())

        // Native-only：不提供渲染器切換選單
        
        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }
    
    // MARK: - Window Menu
    
    private func buildWindowMenu() -> NSMenuItem {
        let windowMenuItem = NSMenuItem(title: "視窗", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "視窗")
        
        // 最小化
        let minimizeItem = NSMenuItem(
            title: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(minimizeItem)
        
        // 縮放
        let zoomItem = NSMenuItem(
            title: "縮放",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(zoomItem)
        
        windowMenu.addItem(NSMenuItem.separator())
        
        // 將全部移至最前
        let bringAllToFrontItem = NSMenuItem(
            title: "將全部移至最前",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(bringAllToFrontItem)
        
        NSApp.windowsMenu = windowMenu
        windowMenuItem.submenu = windowMenu
        return windowMenuItem
    }
    
    // MARK: - Help Menu
    
    private func buildHelpMenu() -> NSMenuItem {
        let helpMenuItem = NSMenuItem(title: "說明", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: "說明")
        
        let helpItem = NSMenuItem(
            title: "Markdown Viewer 說明",
            action: #selector(AppDelegate.showHelp),
            keyEquivalent: "?"
        )
        helpItem.target = appDelegate
        helpMenu.addItem(helpItem)
        
        NSApp.helpMenu = helpMenu
        helpMenuItem.submenu = helpMenu
        return helpMenuItem
    }
}
