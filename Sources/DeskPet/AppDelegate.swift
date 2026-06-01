import AppKit
import SwiftUI
import ApplicationServices
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var window: PetWindow!
    var controller: PetController!
    var httpServer: HTTPServer!
    var isPetVisible = true
    private var focusObserver: NSObjectProtocol?
    private var lastDevApp: NSRunningApplication?

    // MARK: - Fishbowl
    private let fishbowlPopover = NSPopover()
    private var fishbowlHotKeyRef: EventHotKeyRef?
    private var fishbowlHotKeyHandler: EventHandlerRef?

    /// dev app bundle id 白名单 —— 这些是 agent/dev 工作窗口
    /// 在这里面 = 你在工作,桌宠正常 4 秒回 idle
    /// 不在这里面 = 你在别处,桌宠持续庆祝直到你回来
    private let devBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.exafunction.windsurf",        // Windsurf
        "com.openai.codex",                // Codex app
        "com.openai.sky.CUAService",        // Codex Computer Use helper
        "co.anthropic.dt"                  // Claude Desktop(如果有)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityIfNeeded()
        controller = PetController()
        controller.onPetTap = { [weak self] in
            self?.toggleFishbowlPopover()
        }
        controller.onActivateSession = { [weak self] session in
            self?.activateSessionWindow(session)
        }
        setupStatusItem()
        setupWindow()
        controller.start(window: window)
        setupHTTPServer()
        setupFocusObserver()
        setupFishbowlPopover()
        registerFishbowlHotKey()
    }

    // MARK: - Fishbowl popover

    private func setupFishbowlPopover() {
        let content = FishbowlMenuView(
            launcher: FishbowlLauncher.shared,
            onPick: { [weak self] site in
                self?.fishbowlPopover.performClose(nil)
                FishbowlLauncher.shared.openSite(site)
            }
        )
        fishbowlPopover.behavior = .transient
        fishbowlPopover.animates = true
        fishbowlPopover.contentViewController = NSHostingController(rootView: content)
    }

    /// 单击 pet 或 ⌘⌥M 调用。Popover 已显示 → 关掉;否则 → 锚到 pet 窗口上方弹出。
    func toggleFishbowlPopover() {
        if fishbowlPopover.isShown {
            fishbowlPopover.performClose(nil)
            return
        }
        // 每次打开前重新读一次 sites,改了 fishbowl.json 不用重启就生效
        FishbowlLauncher.shared.reload()
        fishbowlPopover.contentViewController = NSHostingController(
            rootView: FishbowlMenuView(
                launcher: FishbowlLauncher.shared,
                onPick: { [weak self] site in
                    self?.fishbowlPopover.performClose(nil)
                    FishbowlLauncher.shared.openSite(site)
                }
            )
        )

        guard let anchor = window?.contentView else { return }
        // 把 popover 浮到 pet 上方:用 pet 角色实际占据的 rect 作锚点
        let petWidth = controller.petSize.width
        let petHeight = controller.petSize.height
        let anchorRect = NSRect(
            x: (anchor.bounds.width - petWidth) / 2,
            y: 0,
            width: petWidth,
            height: petHeight
        )
        // popover 需要窗口能接收点击 — pet 窗口默认 ignoresMouseEvents 是动态的,
        // 但能走到这里说明鼠标在 pet 身上,事件通畅
        window?.level = .floating
        fishbowlPopover.show(relativeTo: anchorRect, of: anchor, preferredEdge: .maxY)
    }

    private func registerFishbowlHotKey() {
        let hotKeyID = EventHotKeyID(signature: 0x52504642, id: 1) // 'RPFB'
        let keyCode: UInt32 = UInt32(kVK_ANSI_M)
        let modifiers: UInt32 = UInt32(cmdKey | optionKey)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.toggleFishbowlPopover() }
                return noErr
            },
            1, &eventType, selfPtr, &fishbowlHotKeyHandler
        )

        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &fishbowlHotKeyRef
        )
        if status != noErr {
            NSLog("Fishbowl: 注册 ⌘⌥M 全局快捷键失败,status=\(status)")
        }
    }

    /// 第一次启动会弹系统提示让用户去 System Settings 授权
    /// 没授权也能跑,只是 click-to-focus 不能精确定位窗口
    private func requestAccessibilityIfNeeded() {
        let options: CFDictionary = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            NSLog("⚠️ 需要 Accessibility 权限才能精确激活特定窗口。请在 System Settings → Privacy & Security → Accessibility 把 DeskPet 加进去。")
        }
    }

    /// 点击 task 列表里的某一行 → 激活那个 session 的具体窗口
    private func activateSessionWindow(_ session: PetSession) {
        // 如果 hook 触发时拿到了具体窗口,优先 raise 之前保存的 AXUIElement
        if let window = session.window {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        // 再把对应 agent app 抬到前台;无窗口 session 用 source 兜底定位 app
        activate(appForSession(session))
    }

    private func appForSession(_ session: PetSession) -> NSRunningApplication {
        let sourceBundleIds: [String]
        switch session.source {
        case "Codex":
            sourceBundleIds = ["com.openai.codex"]
        case "Claude":
            sourceBundleIds = [
                "com.anthropic.claudefordesktop",
                "co.anthropic.dt",
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92"
            ]
        default:
            sourceBundleIds = []
        }

        for bundleId in sourceBundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                return app
            }
        }
        return session.app
    }

    private func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// 点击桌宠 → 激活上次的 dev app 的「上次焦点窗口」(不是任意窗口)
    private func activateLastDevApp() {
        guard let app = lastDevApp else {
            NSLog("tap: no last dev app to activate")
            return
        }

        // 用 Accessibility API 查询 dev app 当前的 focused window
        // (即使 dev app 不是前台,这个属性仍然记录它内部最近的活跃窗口)
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var winRef: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &winRef
        )
        if err == .success, let win = winRef {
            let windowElement = win as! AXUIElement
            // Raise:把这个具体窗口抬到 app 内最前
            AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        } else if err == .apiDisabled || err == .cannotComplete {
            NSLog("Accessibility 权限未授予,只能激活 app 不能定位窗口。err=\(err.rawValue)")
        }

        // 再激活 app 到屏幕最前
        activate(app)
    }

    private func setupFocusObserver() {
        let nc = NSWorkspace.shared.notificationCenter

        // 初始状态
        if let app = NSWorkspace.shared.frontmostApplication {
            let id = app.bundleIdentifier ?? ""
            let isDevApp = devBundleIds.contains(id)
            if isDevApp { lastDevApp = app }
            controller.updateFocus(isInDevApp: isDevApp)
        }

        focusObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self,
                  let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let id = app.bundleIdentifier ?? ""
            let isDevApp = self.devBundleIds.contains(id)
            // 记住最近一次 dev app(用于点击桌宠跳回去)
            if isDevApp { self.lastDevApp = app }
            self.controller.updateFocus(isInDevApp: isDevApp)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🔥"
        }
        rebuildStatusMenu()
    }

    /// 构建并挂上状态栏菜单(复用现有 statusItem,切语言时只重建菜单,不重建图标)。
    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: Lang.t("显示 / 隐藏", "Show / Hide"), action: #selector(toggleVisibility), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: Lang.t("贴边 / 出来", "Dock / Undock"), action: #selector(toggleMiniMode), keyEquivalent: "m"))

        // 角色切换子菜单
        let characterMenuItem = NSMenuItem(title: Lang.t("切换角色", "Character"), action: nil, keyEquivalent: "")
        let characterSubMenu = NSMenu()
        characterSubMenu.delegate = self
        characterSubMenu.identifier = NSUserInterfaceItemIdentifier("character-list")
        characterMenuItem.submenu = characterSubMenu
        menu.addItem(characterMenuItem)

        // 语言子菜单
        let langMenuItem = NSMenuItem(title: Lang.t("语言", "Language"), action: nil, keyEquivalent: "")
        let langSubMenu = NSMenu()
        let langOptions: [(title: String, code: String?)] = [
            (Lang.t("跟随系统", "Follow system"), nil),
            ("中文", "zh"),
            ("English", "en"),
        ]
        for opt in langOptions {
            let item = NSMenuItem(title: opt.title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.code
            if Lang.override == opt.code { item.state = .on }
            langSubMenu.addItem(item)
        }
        langMenuItem.submenu = langSubMenu
        menu.addItem(langMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: Lang.t("🪲 走一下", "🪲 Walk"), action: #selector(debugWalk), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: Lang.t("🪲 思考(火焰)", "🪲 Think (flames)"), action: #selector(debugThinking), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: Lang.t("🪲 完成(庆祝)", "🪲 Done (celebrate)"), action: #selector(debugDone), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: Lang.t("🪲 显示气泡", "🪲 Show bubble"), action: #selector(debugBubble), keyEquivalent: "b"))
        menu.addItem(NSMenuItem(title: Lang.t("🪲 睡一下", "🪲 Sleep"), action: #selector(debugRest), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: Lang.t("🪲 醒来", "🪲 Wake"), action: #selector(debugIdle), keyEquivalent: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: Lang.t("退出", "Quit"), action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    /// 切换语言:nil 跟随系统,"zh"/"en" 强制。重建菜单让标题立即变。
    @objc private func setLanguage(_ sender: NSMenuItem) {
        Lang.override = sender.representedObject as? String
        rebuildStatusMenu()
    }

    @objc private func switchCharacterAction(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String else { return }
        controller.switchCharacter(slug)
    }

    // MARK: - NSMenuDelegate(动态填充角色列表,菜单弹开前)
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier?.rawValue == "character-list" else { return }
        menu.removeAllItems()
        let slugs = CharacterRegistry.allSlugs()
        if slugs.isEmpty {
            let placeholder = NSMenuItem(title: "(没有可用角色)", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
            return
        }
        for slug in slugs {
            let title = CharacterRegistry.displayName(for: slug)
            let item = NSMenuItem(title: title, action: #selector(switchCharacterAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = slug
            // 当前角色打勾
            if slug == controller.currentCharacter {
                item.state = .on
            }
            menu.addItem(item)
        }
    }

    private func setupWindow() {
        window = PetWindow(controller: controller)
        window.orderFrontRegardless()
    }

    private func setupHTTPServer() {
        httpServer = HTTPServer()
        httpServer.onState = { [weak self] stateName in
            guard let self = self else { return }
            guard let newState = PetState(rawValue: stateName) else {
                NSLog("HTTPServer: unknown state '\(stateName)'")
                return
            }
            self.controller.setExternalState(newState)
        }
        httpServer.onTask = { [weak self] taskText in
            self?.controller.showTaskBubble(taskText)
        }
        httpServer.onPrompt = { [weak self] promptText, sessionId, source in
            self?.controller.recordPrompt(promptText, sessionId: sessionId, source: source)
        }
        httpServer.onSessionDone = { [weak self] sessionId, source in
            self?.controller.markSessionDone(sessionId: sessionId, source: source)
        }
        httpServer.start()
    }

    @objc private func toggleMiniMode() {
        controller.toggleMiniMode()
    }

    @objc private func toggleVisibility() {
        isPetVisible.toggle()
        if isPetVisible {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    @objc private func debugWalk() { controller.debugForceWalk() }
    @objc private func debugThinking() { controller.debugForceThinking() }
    @objc private func debugDone() { controller.debugForceDone() }
    @objc private func debugBubble() { controller.debugShowBubble() }
    @objc private func debugRest() { controller.debugForceRest() }
    @objc private func debugIdle() { controller.debugForceIdle() }

    @objc private func quit() {
        if let observer = focusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        httpServer?.stop()
        controller?.stop()
        NSApp.terminate(nil)
    }
}
