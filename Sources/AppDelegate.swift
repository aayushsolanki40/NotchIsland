import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: IslandModel!
    private var controller: IslandWindowController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two overlapping islands fight over clicks, so the newest launch wins.
        let me = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
            .forEach { $0.terminate() }

        model = IslandModel()
        controller = IslandWindowController(model: model)
        controller.show()
        model.start()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchIsland")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in IslandStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = model.style == style ? .on : .off
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        let hover = NSMenuItem(title: "Expand on Hover", action: #selector(toggleHover), keyEquivalent: "")
        hover.target = self
        hover.state = model.expandOnHover ? .on : .off
        menu.addItem(hover)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        for (title, sel) in [("Preview Charging", #selector(previewCharging)),
                             ("Preview Low Battery", #selector(previewLowBattery)),
                             ("Preview AirPods", #selector(previewAirPods)),
                             ("Start 10s Timer", #selector(previewTimer))] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchIsland", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = IslandStyle(rawValue: raw) else { return }
        model.style = style
        controller.reposition()
        rebuildMenu()
    }

    @objc private func toggleHover() {
        model.expandOnHover.toggle()
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
        rebuildMenu()
    }

    @objc private func previewCharging() {
        model.showTransient(.charging)
    }

    @objc private func previewLowBattery() {
        model.battery.previewLowBattery()
    }

    @objc private func previewAirPods() {
        model.bluetooth.preview()
    }

    @objc private func previewTimer() {
        model.timer.start(seconds: 10)
    }
}
