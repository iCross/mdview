// MenuBuilder.swift
// macOS Markdown Viewer - Menu construction

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
        
        // Application menu
        mainMenu.addItem(buildAppMenu())
        
        // File menu
        mainMenu.addItem(buildFileMenu())
        
        // Edit menu
        mainMenu.addItem(buildEditMenu())
        
        // View menu
        mainMenu.addItem(buildViewMenu())
        
        // Window menu
        mainMenu.addItem(buildWindowMenu())
        
        // Help menu
        mainMenu.addItem(buildHelpMenu())
        
        return mainMenu
    }
    
    // MARK: - App Menu
    
    private func buildAppMenu() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        
        // About
        let aboutItem = NSMenuItem(
            title: "About Markdown Viewer",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Services
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        NSApp.servicesMenu = servicesMenu
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Hide app
        let hideItem = NSMenuItem(
            title: "Hide Markdown Viewer",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)
        
        // Hide others
        let hideOthersItem = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        
        // Show all
        let showAllItem = NSMenuItem(
            title: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(showAllItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Markdown Viewer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)
        
        appMenuItem.submenu = appMenu
        return appMenuItem
    }
    
    // MARK: - File Menu
    
    private func buildFileMenu() -> NSMenuItem {
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        
        // Open
        let openItem = NSMenuItem(
            title: "Open…",
            action: #selector(AppDelegate.openFile),
            keyEquivalent: "o"
        )
        openItem.target = appDelegate
        fileMenu.addItem(openItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        // Reload
        let reloadItem = NSMenuItem(
            title: "Reload",
            action: #selector(AppDelegate.reloadCurrentFile),
            keyEquivalent: "r"
        )
        reloadItem.target = appDelegate
        fileMenu.addItem(reloadItem)
        
        fileMenu.addItem(NSMenuItem.separator())
        
        // Close window
        let closeItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileMenu.addItem(closeItem)
        
        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }
    
    // MARK: - Edit Menu
    
    private func buildEditMenu() -> NSMenuItem {
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        
        // Copy
        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(copyItem)
        
        // Copy Full Content
        let copyFullContentItem = NSMenuItem(
            title: "Copy Full Content",
            action: #selector(AppDelegate.copyFullContent),
            keyEquivalent: "C" // Capital C means Cmd+Shift+C
        )
        copyFullContentItem.target = appDelegate
        editMenu.addItem(copyFullContentItem)
        
        // Select All
        let selectAllItem = NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(selectAllItem)

        editMenu.addItem(NSMenuItem.separator())

        // Find submenu
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")

        let findPanelItem = NSMenuItem(
            title: "Find…",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "f"
        )
        findPanelItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        findMenu.addItem(findPanelItem)

        let findNextItem = NSMenuItem(
            title: "Find Next",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "g"
        )
        findNextItem.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
        findMenu.addItem(findNextItem)

        let findPrevItem = NSMenuItem(
            title: "Find Previous",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "g"
        )
        findPrevItem.keyEquivalentModifierMask = [.command, .shift]
        findPrevItem.tag = Int(NSTextFinder.Action.previousMatch.rawValue)
        findMenu.addItem(findPrevItem)

        let useSelectionItem = NSMenuItem(
            title: "Use Selection for Find",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "e"
        )
        useSelectionItem.tag = Int(NSTextFinder.Action.setSearchString.rawValue)
        findMenu.addItem(useSelectionItem)

        findItem.submenu = findMenu
        editMenu.addItem(findItem)
        
        editMenuItem.submenu = editMenu
        return editMenuItem
    }
    
    // MARK: - View Menu
    
    private func buildViewMenu() -> NSMenuItem {
        let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        
        // Enter Full Screen
        let fullScreenItem = NSMenuItem(
            title: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)
        
        viewMenu.addItem(NSMenuItem.separator())
        
        // Zoom In
        let zoomInItem = NSMenuItem(
            title: "Zoom In",
            action: #selector(AppDelegate.zoomIn),
            keyEquivalent: "+"
        )
        zoomInItem.target = appDelegate
        viewMenu.addItem(zoomInItem)
        
        // Zoom Out
        let zoomOutItem = NSMenuItem(
            title: "Zoom Out",
            action: #selector(AppDelegate.zoomOut),
            keyEquivalent: "-"
        )
        zoomOutItem.target = appDelegate
        viewMenu.addItem(zoomOutItem)
        
        // Actual Size
        let actualSizeItem = NSMenuItem(
            title: "Actual Size",
            action: #selector(AppDelegate.resetZoom),
            keyEquivalent: "0"
        )
        actualSizeItem.target = appDelegate
        viewMenu.addItem(actualSizeItem)
        
        viewMenu.addItem(NSMenuItem.separator())

        // Theme
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        
        let themeSystem = NSMenuItem(title: "System", action: #selector(AppDelegate.setThemeSystem), keyEquivalent: "")
        themeSystem.target = appDelegate
        themeMenu.addItem(themeSystem)
        
        let themeLight = NSMenuItem(title: "Light", action: #selector(AppDelegate.setThemeLight), keyEquivalent: "")
        themeLight.target = appDelegate
        themeMenu.addItem(themeLight)
        
        let themeDark = NSMenuItem(title: "Dark", action: #selector(AppDelegate.setThemeDark), keyEquivalent: "")
        themeDark.target = appDelegate
        themeMenu.addItem(themeDark)
        
        themeItem.submenu = themeMenu
        viewMenu.addItem(themeItem)
        
        viewMenu.addItem(NSMenuItem.separator())

        // Native-only: no renderer switching menu
        
        viewMenuItem.submenu = viewMenu
        return viewMenuItem
    }
    
    // MARK: - Window Menu
    
    private func buildWindowMenu() -> NSMenuItem {
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        
        // Minimize
        let minimizeItem = NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(minimizeItem)
        
        // Zoom
        let zoomItem = NSMenuItem(
            title: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(zoomItem)
        
        // Merge All Windows (Tabs)
        let mergeItem = NSMenuItem(
            title: "Merge All Windows",
            action: #selector(NSWindow.mergeAllWindows(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(mergeItem)
        
        windowMenu.addItem(NSMenuItem.separator())
        
        // Bring All to Front
        let bringAllToFrontItem = NSMenuItem(
            title: "Bring All to Front",
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
        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        let helpMenu = NSMenu(title: "Help")
        
        let helpItem = NSMenuItem(
            title: "Markdown Viewer Help",
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
