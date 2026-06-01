import AppKit
import SwiftUI
import Combine

final class PetController: ObservableObject {
    @Published var state: PetState = .idle {
        didSet {
            if oldValue != state {
                onStateChanged()
            }
        }
    }
    @Published var isBlinking: Bool = false
    @Published var facing: Direction = .left
    @Published var frameIndex: Int = 0
    @Published var taskBubbleText: String? = nil

    /// 当前角色 slug,默认 example,UserDefaults 持久化
    @Published var currentCharacter: String = UserDefaults.standard.string(forKey: "currentCharacter") ?? "example"

    // MARK: - Hover 任务切换器
    @Published var sessions: [PetSession] = []
    @Published var showTaskList: Bool = false
    private var taskListHideTimer: Timer?

    /// 当前 sprite 的 base name(不含角色前缀)。PetView 配合 currentCharacter 加载。
    var currentSpriteBaseName: String {
        // Mini mode 且静止时始终用 peek_<edge>(探头/缩回都保持扒墙姿态,不切回 idle)
        // 优先 peek_<edge> → peek → idle 回退(没 peek 帧时靠窗口越界裁切达到"半身露出")
        if isMiniMode && (state == .idle || state == .resting) {
            let edgeName = miniEdge == .right ? "peek_right" : "peek_left"
            if SpriteCache.image(character: currentCharacter, baseName: edgeName) != nil {
                return edgeName
            }
            if SpriteCache.image(character: currentCharacter, baseName: "peek") != nil {
                return "peek"
            }
        }
        if isBlinking && state == .idle {
            return "blink"
        }
        let frames = state.frames
        if frames.isEmpty { return "idle" }
        let idx = min(max(frameIndex, 0), frames.count - 1)
        return frames[idx]
    }

    /// 切换角色 → 清 sprite 缓存 + 写偏好
    func switchCharacter(_ slug: String) {
        guard slug != currentCharacter else { return }
        SpriteCache.invalidate()
        currentCharacter = slug
        UserDefaults.standard.set(slug, forKey: "currentCharacter")
    }

    // MARK: - Window 关联
    weak var window: NSWindow?
    var petSize = NSSize(width: 130, height: 156)   // 角色实际尺寸
    var windowSize = NSSize(width: 240, height: 340) // 窗口含气泡/任务列表区域
    private var floorY: CGFloat = 100

    // MARK: - 定时器
    private var blinkTimer: Timer?
    private var walkScheduleTimer: Timer?
    private var walkAnimator: Timer?
    private var systemMonitorTimer: Timer?
    private var frameAnimator: Timer?
    private var taskBubbleTimer: Timer?
    private var doneAutoExitTimer: Timer?

    // MARK: - 走动状态
    private var positionX: CGFloat = 0
    private var walkTarget: CGFloat?
    private var walkSpeed: CGFloat = 0

    // MARK: - 拖拽状态
    private var dragStartFrame: NSPoint?
    private var dragStartMouse: NSPoint?
    private var dragTickTimer: Timer?
    private(set) var isDragging: Bool = false

    // MARK: - 系统事件
    private var stateBeforeAutoRest: PetState = .idle
    private var isInAutoRest: Bool = false

    // MARK: - 焦点检测(用户是否在 dev/agent 窗口)
    /// true = 当前焦点在 dev app(Terminal / iTerm / VS Code / Cursor 等)
    /// false = 焦点在其他 app(浏览器 / Slack / 视频…),done 状态会持久挂住
    @Published var isInDevApp: Bool = true

    // MARK: - Mini Mode(贴边躲到屏幕外只露半身)
    enum MiniEdge { case left, right }

    @Published private(set) var isMiniMode: Bool = false
    @Published private(set) var isPeeking: Bool = false
    private(set) var miniEdge: MiniEdge = .right

    /// 拖动结束时,距屏幕边小于此阈值就吸附进 mini mode
    private let edgeSnapThreshold: CGFloat = 70
    /// Mini mode 隐藏时,留在屏幕内的窗口宽度。
    /// 窗口内角色居中,左右各有 ~55px 空白。这里取 100 让角色左/右 ~45px 真正露出来。
    private let peekVisibleWidth: CGFloat = 100

    private var peekHideTimer: Timer?
    private var parabolaTimer: Timer?

    // MARK: - 帧动画
    private var frameDirection: Int = 1

    // MARK: - 生命周期
    func start(window: NSWindow) {
        self.window = window
        guard let screen = NSScreen.main else { return }
        floorY = screen.frame.minY + 60
        positionX = screen.frame.maxX - windowSize.width - 30
        window.setFrameOrigin(NSPoint(x: positionX, y: floorY))

        scheduleBlink()
        scheduleNextWalk()
        startSystemMonitor()
        onStateChanged()
    }

    func stop() {
        [blinkTimer, walkScheduleTimer, walkAnimator, systemMonitorTimer,
         frameAnimator, taskBubbleTimer, doneAutoExitTimer, taskListHideTimer,
         dragTickTimer, peekHideTimer, parabolaTimer]
            .forEach { $0?.invalidate() }
    }

    private func makeTimer(after seconds: TimeInterval, repeats: Bool = false, _ block: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: seconds, repeats: repeats) { _ in block() }
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    // MARK: - 状态切换
    private func onStateChanged() {
        frameAnimator?.invalidate()
        frameAnimator = nil
        frameIndex = 0
        frameDirection = 1

        // 进入 done(完成庆祝)时播一下角色对应的系统音
        if state == .done {
            playDoneSound()
        }

        let frames = state.frames
        guard frames.count > 1 else { return }
        let interval = 1.0 / state.fps
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
        RunLoop.main.add(t, forMode: .common)
        frameAnimator = t
    }

    private func playDoneSound() {
        let name = CharacterRegistry.doneSoundName(for: currentCharacter)
        let path = "/System/Library/Sounds/\(name).aiff"
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("playDoneSound: 找不到音频 \(path)")
            return
        }
        let p = Process()
        p.launchPath = "/usr/bin/afplay"
        p.arguments = ["-v", "3", path]   // -v 3 = 三倍音量,弥补系统音设计偏小
        do {
            try p.run()
        } catch {
            NSLog("playDoneSound: afplay 启动失败 \(error)")
        }
    }

    private func advanceFrame() {
        let count = state.frames.count
        guard count > 1 else { return }
        var next = frameIndex + frameDirection
        if next >= count {
            next = count - 2
            frameDirection = -1
        } else if next < 0 {
            next = 1
            frameDirection = 1
        }
        next = min(max(next, 0), count - 1)
        frameIndex = next
    }

    // MARK: - 眨眼
    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let interval = Double.random(in: 4...7)
        blinkTimer = makeTimer(after: interval) { [weak self] in
            self?.doBlink()
        }
    }

    private func doBlink() {
        guard state == .idle else {
            scheduleBlink()
            return
        }
        isBlinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.isBlinking = false
            self?.scheduleBlink()
        }
    }

    // MARK: - 走动
    private func scheduleNextWalk() {
        walkScheduleTimer?.invalidate()
        if isMiniMode { return }   // mini mode 下不安排走动
        let interval = Double.random(in: 12...25)
        walkScheduleTimer = makeTimer(after: interval) { [weak self] in
            self?.startWalk()
        }
    }

    func startWalk() {
        guard !isMiniMode, state == .idle, let screen = NSScreen.main, let window = self.window else {
            scheduleNextWalk()
            return
        }
        let minX = screen.frame.minX + 30
        let maxX = screen.frame.maxX - windowSize.width - 30
        var target = CGFloat.random(in: minX...maxX)
        if abs(target - positionX) < 80 {
            target = (positionX < (minX + maxX) / 2) ? maxX : minX
        }
        walkTarget = target
        walkSpeed = target > positionX ? 0.7 : -0.7
        facing = target > positionX ? .right : .left
        state = .walking

        walkAnimator?.invalidate()
        walkAnimator = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickWalk()
        }
        if let t = walkAnimator {
            RunLoop.main.add(t, forMode: .common)
        }
        _ = window
    }

    private func tickWalk() {
        guard let target = walkTarget, let window = self.window else { return }
        positionX += walkSpeed
        window.setFrameOrigin(NSPoint(x: positionX, y: floorY))
        if abs(positionX - target) < 1 {
            walkAnimator?.invalidate()
            walkAnimator = nil
            walkTarget = nil
            state = .idle
            scheduleNextWalk()
        }
    }

    // MARK: - 鼠标拖拽
    // 用 60fps 定时器读 NSEvent.mouseLocation(屏幕坐标),算 delta 后直接 setFrameOrigin。
    // 不依赖 SwiftUI 的 translation——窗口移动后 SwiftUI 坐标会漂移。
    func startDrag() {
        guard let window = self.window else { return }
        isDragging = true
        dragStartFrame = window.frame.origin
        dragStartMouse = NSEvent.mouseLocation
        // 取消自动走路
        walkAnimator?.invalidate()
        walkAnimator = nil
        walkTarget = nil
        walkSpeed = 0
        walkScheduleTimer?.invalidate()
        if state == .walking {
            state = .idle
        }

        // 60fps 拉鼠标坐标
        dragTickTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.dragTick()
        }
        RunLoop.main.add(t, forMode: .common)
        dragTickTimer = t
    }

    private func dragTick() {
        guard let window = self.window,
              let startFrame = dragStartFrame,
              let startMouse = dragStartMouse else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - startMouse.x
        let dy = current.y - startMouse.y
        window.setFrameOrigin(NSPoint(x: startFrame.x + dx, y: startFrame.y + dy))
    }

    func endDrag() {
        dragTickTimer?.invalidate()
        dragTickTimer = nil
        guard let window = self.window, let screen = NSScreen.main else {
            isDragging = false
            return
        }
        let origin = window.frame.origin
        let distRight = screen.frame.maxX - (origin.x + windowSize.width)
        let distLeft = origin.x - screen.frame.minX
        dragStartFrame = nil
        dragStartMouse = nil
        isDragging = false

        // 边缘吸附 → mini mode
        if distRight < edgeSnapThreshold {
            floorY = origin.y
            enterMiniMode(edge: .right)
            return
        }
        if distLeft < edgeSnapThreshold {
            floorY = origin.y
            enterMiniMode(edge: .left)
            return
        }
        // 拖到中间 → 退出 mini mode(如果之前在)+ 正常 home
        if isMiniMode {
            isMiniMode = false
            isPeeking = false
            peekHideTimer?.invalidate()
        }
        positionX = origin.x
        floorY = origin.y
        scheduleNextWalk()
    }

    // MARK: - 系统事件
    private func startSystemMonitor() {
        systemMonitorTimer?.invalidate()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkSystem()
        }
        RunLoop.main.add(t, forMode: .common)
        systemMonitorTimer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkSystem()
        }
    }

    private func checkSystem() {
        // Mini mode 下桌宠是"停靠"状态,不进自动休息(否则探头时会露出睡觉帧)
        if isMiniMode { return }
        guard state.canBeInterrupted else { return }
        let battery = SystemMonitor.batteryPercentage()
        let idle = SystemMonitor.idleSeconds()
        let deepNight = SystemMonitor.isDeepNight()
        let lowBattery = (battery ?? 100) < 20
        let longIdle = idle > 300
        let shouldRest = lowBattery || longIdle || deepNight

        if shouldRest && !isInAutoRest {
            stateBeforeAutoRest = (state == .walking) ? .idle : state
            isInAutoRest = true
            walkAnimator?.invalidate()
            walkAnimator = nil
            walkTarget = nil
            state = .resting
        } else if !shouldRest && isInAutoRest {
            isInAutoRest = false
            state = stateBeforeAutoRest
            scheduleNextWalk()
        }
    }

    // MARK: - Session 追踪(hook 调用)
    /// UserPromptSubmit hook 触发时调用:记录这条 prompt + 当前焦点窗口 + agent session id
    func recordPrompt(_ prompt: String, sessionId: String?, source: String? = nil) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var winRef: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winRef)
        let win: AXUIElement? = (err == .success && winRef != nil) ? (winRef as! AXUIElement) : nil
        if win == nil {
            NSLog("recordPrompt: 无法获取焦点窗口,err=\(err.rawValue),继续记录无窗口 session")
        }

        let trimmedLabel = prompt.count > 40 ? String(prompt.prefix(38)) + "…" : prompt
        let agentSource = normalizedSource(source)

        if let sid = sessionId,
           let idx = sessions.firstIndex(where: { $0.externalSessionId == sid && $0.source == agentSource }) {
            sessions[idx].label = trimmedLabel
            sessions[idx].lastActivity = Date()
            sessions[idx].isDone = false
            if let win = win, sessions[idx].window == nil {
                sessions[idx].window = win
            }
        } else if let win = win,
                  let idx = sessions.firstIndex(where: { existing in
                      guard let existingWindow = existing.window else { return false }
                      return CFEqual(existingWindow, win) && existing.source == agentSource
                  }) {
            sessions[idx].label = trimmedLabel
            sessions[idx].lastActivity = Date()
            sessions[idx].isDone = false   // 又发消息了,回到 thinking
            if let sid = sessionId, sessions[idx].externalSessionId == nil {
                sessions[idx].externalSessionId = sid
            }
        } else {
            let newSession = PetSession(
                id: UUID().uuidString,
                label: trimmedLabel,
                source: agentSource,
                app: app,
                window: win,
                lastActivity: Date(),
                externalSessionId: sessionId,
                isDone: false
            )
            sessions.append(newSession)
        }

        // GC 超过 2 小时无活动的 session
        let cutoff = Date().addingTimeInterval(-7200)
        sessions.removeAll { $0.lastActivity < cutoff }

        // 按最近活动排序(新的在前)
        sessions.sort { $0.lastActivity > $1.lastActivity }
    }

    /// Stop hook 触发时调用:把对应 session 标记为 done(列表显示绿色)
    func markSessionDone(sessionId: String, source: String? = nil) {
        let agentSource = normalizedSource(source)
        if let idx = sessions.firstIndex(where: { $0.externalSessionId == sessionId && $0.source == agentSource }) {
            sessions[idx].isDone = true
            sessions[idx].lastActivity = Date()
        } else if let idx = sessions.firstIndex(where: { !$0.isDone && $0.source == agentSource }) {
            sessions[idx].isDone = true
            sessions[idx].lastActivity = Date()
        }
    }

    private func normalizedSource(_ source: String?) -> String {
        let trimmed = (source ?? "Claude").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Claude" : trimmed
    }

    /// 点击 task 列表里的一行 → 激活那个 session 的窗口
    var onActivateSession: ((PetSession) -> Void)?
    func activateSession(_ session: PetSession) {
        onActivateSession?(session)
        // 选中后隐藏列表
        showTaskList = false
        taskListHideTimer?.invalidate()
    }

    /// 鼠标 hover 进入桌宠 hot zone
    func hoverEnter() {
        taskListHideTimer?.invalidate()
        if isMiniMode {
            // 探头会把整个窗口滑回屏内,任务列表才有空间完整显示
            peekOut()
        }
        if !sessions.isEmpty {
            showTaskList = true
        }
    }

    /// 鼠标 hover 离开 → 延迟 500ms 隐藏(给鼠标移到列表的时间)
    func hoverExit() {
        taskListHideTimer?.invalidate()
        if isMiniMode {
            peekIn()
        }
        taskListHideTimer = makeTimer(after: 0.5) { [weak self] in
            self?.showTaskList = false
        }
    }

    // MARK: - 任务气泡
    func showTaskBubble(_ text: String, duration: TimeInterval = 6) {
        // 截断过长内容
        let trimmed = text.count > 60 ? String(text.prefix(57)) + "…" : text
        taskBubbleText = trimmed
        taskBubbleTimer?.invalidate()
        taskBubbleTimer = makeTimer(after: duration) { [weak self] in
            self?.taskBubbleText = nil
            if self?.isMiniMode == true { self?.peekIn() }
        }
        // Mini mode 下露全身,让气泡完整可见
        if isMiniMode, let screen = NSScreen.main {
            peekHideTimer?.invalidate()
            if !isPeeking {
                isPeeking = true
                animateWindow(to: shownOrigin(screen: screen, edge: miniEdge), duration: 0.22)
            }
        }
    }

    // MARK: - 调试入口
    func debugForceWalk() {
        if state != .idle {
            walkAnimator?.invalidate()
            walkAnimator = nil
            walkTarget = nil
            isInAutoRest = false
            state = .idle
        }
        startWalk()
    }

    func debugForceRest() {
        walkAnimator?.invalidate()
        walkAnimator = nil
        walkTarget = nil
        stateBeforeAutoRest = .idle
        isInAutoRest = true
        state = .resting
    }

    func debugForceIdle() {
        walkAnimator?.invalidate()
        walkAnimator = nil
        walkTarget = nil
        isInAutoRest = false
        state = .idle
        scheduleNextWalk()
    }

    func debugForceThinking() {
        walkAnimator?.invalidate()
        walkAnimator = nil
        walkTarget = nil
        state = .thinking
    }

    func debugForceDone() {
        walkAnimator?.invalidate()
        walkAnimator = nil
        walkTarget = nil
        state = .done
        scheduleAutoDoneExit()
    }

    func debugShowBubble() {
        showTaskBubble("调试:正在测试任务气泡显示")
    }

    // MARK: - Mini Mode
    /// 由 AppDelegate / 菜单调用,切换 mini mode
    func toggleMiniMode() {
        if isMiniMode {
            exitMiniMode()
        } else {
            guard let screen = NSScreen.main else { return }
            let distLeft = positionX - screen.frame.minX
            let distRight = screen.frame.maxX - (positionX + windowSize.width)
            enterMiniMode(edge: distLeft < distRight ? .left : .right)
        }
    }

    private func enterMiniMode(edge: MiniEdge) {
        guard let screen = NSScreen.main else { return }
        isMiniMode = true
        miniEdge = edge
        isPeeking = false
        // 停 walk + 走动相关
        walkAnimator?.invalidate(); walkAnimator = nil
        walkTarget = nil
        walkScheduleTimer?.invalidate()
        // 清掉可能在停靠前已进入的自动休息,强制 idle,保证探头时不露睡觉帧
        isInAutoRest = false
        if state != .idle { state = .idle }
        // 朝屏幕内
        facing = (edge == .right) ? .left : .right
        positionX = hiddenOrigin(screen: screen, edge: edge).x
        animateWindow(to: hiddenOrigin(screen: screen, edge: edge), duration: 0.32)
    }

    private func exitMiniMode() {
        guard let screen = NSScreen.main else { return }
        isMiniMode = false
        isPeeking = false
        peekHideTimer?.invalidate()
        parabolaTimer?.invalidate(); parabolaTimer = nil
        let safeX = (miniEdge == .right)
            ? screen.frame.maxX - windowSize.width - 30
            : screen.frame.minX + 30
        positionX = safeX
        animateWindow(to: NSPoint(x: safeX, y: floorY), duration: 0.3)
        scheduleNextWalk()
    }

    private func hiddenOrigin(screen: NSScreen, edge: MiniEdge) -> NSPoint {
        switch edge {
        case .right:
            return NSPoint(x: screen.frame.maxX - peekVisibleWidth, y: floorY)
        case .left:
            return NSPoint(x: screen.frame.minX - windowSize.width + peekVisibleWidth, y: floorY)
        }
    }

    private func shownOrigin(screen: NSScreen, edge: MiniEdge) -> NSPoint {
        switch edge {
        case .right:
            return NSPoint(x: screen.frame.maxX - windowSize.width, y: floorY)
        case .left:
            return NSPoint(x: screen.frame.minX, y: floorY)
        }
    }

    private func animateWindow(to origin: NSPoint, duration: TimeInterval) {
        guard let window = self.window else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(origin)
        }
    }

    private func peekOut() {
        guard isMiniMode, let screen = NSScreen.main else { return }
        peekHideTimer?.invalidate()
        if isPeeking { return }
        isPeeking = true
        animateWindow(to: shownOrigin(screen: screen, edge: miniEdge), duration: 0.22)
    }

    private func peekIn() {
        guard isMiniMode, isPeeking else { return }
        peekHideTimer?.invalidate()
        peekHideTimer = makeTimer(after: 0.5) { [weak self] in
            guard let self = self, self.isMiniMode, let screen = NSScreen.main else { return }
            self.isPeeking = false
            self.animateWindow(to: self.hiddenOrigin(screen: screen, edge: self.miniEdge), duration: 0.28)
        }
    }

    /// Mini mode 下 done/通知触发的抛物线小跳
    private func parabolicJump(peakHeight: CGFloat = 36, duration: TimeInterval = 0.55) {
        guard let window = self.window else { return }
        parabolaTimer?.invalidate()
        let baseY = window.frame.origin.y
        let startTime = Date()
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self, let win = self.window else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed >= duration {
                win.setFrameOrigin(NSPoint(x: win.frame.origin.x, y: baseY))
                timer.invalidate()
                self.parabolaTimer = nil
                return
            }
            let p = elapsed / duration
            let yOff = 4.0 * peakHeight * CGFloat(p) * (1.0 - CGFloat(p))
            win.setFrameOrigin(NSPoint(x: win.frame.origin.x, y: baseY + yOff))
        }
        RunLoop.main.add(t, forMode: .common)
        parabolaTimer = t
    }

    /// Mini mode 下 done 的庆祝:露全身 + 抛物线小跳
    private func celebrateInMiniMode() {
        guard isMiniMode, let screen = NSScreen.main else { return }
        peekHideTimer?.invalidate()
        if !isPeeking {
            isPeeking = true
            animateWindow(to: shownOrigin(screen: screen, edge: miniEdge), duration: 0.2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            self?.parabolicJump()
        }
    }

    // MARK: - 外部 hook 入口
    func setExternalState(_ newState: PetState) {
        walkAnimator?.invalidate()
        walkAnimator = nil
        walkTarget = nil
        isInAutoRest = false
        state = newState

        if newState == .done {
            if isMiniMode { celebrateInMiniMode() }
            scheduleAutoDoneExit()
        } else if newState == .idle {
            scheduleNextWalk()
            if isMiniMode { peekIn() }
        }
    }

    private func scheduleAutoDoneExit() {
        doneAutoExitTimer?.invalidate()
        // 只有焦点在 dev app 时才计划自动退出 done;
        // 不在 dev app 时,done 状态持久挂住(召唤用户回来)
        guard isInDevApp else { return }
        doneAutoExitTimer = makeTimer(after: 4.0) { [weak self] in
            guard let self = self else { return }
            if self.state == .done {
                self.state = .idle
                self.scheduleNextWalk()
            }
        }
    }

    /// 点击桌宠触发的回调(由 AppDelegate 注入,激活上次的 dev app)
    var onPetTap: (() -> Void)?

    func handlePetTap() {
        onPetTap?()
    }

    /// 由 AppDelegate 的焦点观察者调用
    func updateFocus(isInDevApp newValue: Bool) {
        let wasInDevApp = self.isInDevApp
        self.isInDevApp = newValue

        if !newValue {
            // 失去 dev app 焦点 → 取消挂着的 done 自动退出
            doneAutoExitTimer?.invalidate()
            doneAutoExitTimer = nil
        } else if !wasInDevApp && state == .done {
            // 用户刚切回 dev app,且当前还在 done → 现在开始 4 秒倒计时
            scheduleAutoDoneExit()
        }
    }
}
