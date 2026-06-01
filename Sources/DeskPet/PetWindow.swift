import AppKit
import SwiftUI

class PetWindow: NSWindow {
    let controller: PetController
    private var mouseTrackingTimer: Timer?
    /// Mini mode 下我们自己驱动 hover(SwiftUI .onHover 在屏幕外的 Image 上不会触发)
    private var lastMouseOverActiveInMini: Bool = false

    init(controller: PetController) {
        self.controller = controller
        let size = controller.windowSize
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let origin = NSPoint(
            x: screen.frame.maxX - size.width - 30,
            y: screen.frame.minY + 60
        )

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // 初始忽略点击;mouseTrackingTimer 会根据鼠标位置动态切换
        self.ignoresMouseEvents = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: PetView(controller: controller))
        host.frame = NSRect(origin: .zero, size: size)
        self.contentView = host

        startMouseTracking()
    }

    deinit {
        mouseTrackingTimer?.invalidate()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 每 100ms 检查鼠标位置:在桌宠身体上 → 开启点击;不在 → 关闭点击(穿透)
    private func startMouseTracking() {
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateMouseEventHandling()
        }
        RunLoop.main.add(t, forMode: .common)
        mouseTrackingTimer = t
    }

    private func updateMouseEventHandling() {
        // 拖拽中:强制接收鼠标事件,否则 drag 流会被打断(鼠标稍快脱离 body → 100ms 后 drag 断了)
        if controller.isDragging {
            if ignoresMouseEvents {
                ignoresMouseEvents = false
            }
            return
        }

        let mouseLoc = NSEvent.mouseLocation   // 屏幕坐标
        let petWidth = controller.petSize.width
        let petHeight = controller.petSize.height
        let petScreenRect = NSRect(
            x: frame.origin.x + (frame.width - petWidth) / 2,
            y: frame.origin.y,
            width: petWidth,
            height: petHeight
        )

        // hot zone 选择:
        //   - Mini mode → 整个 window frame(露在屏幕内的那条都算)
        //   - hover task 列表显示中 → 整个窗口(避免鼠标移到列表上就关掉)
        //   - 其余 → 仅角色实际占据的 rect
        let activeRect: NSRect
        if controller.isMiniMode || controller.showTaskList {
            activeRect = frame
        } else {
            activeRect = petScreenRect
        }
        let mouseOverActive = activeRect.contains(mouseLoc)
        if ignoresMouseEvents == mouseOverActive {
            ignoresMouseEvents = !mouseOverActive
        }

        // Mini mode 下角色 image 在屏幕外,SwiftUI 的 .onHover 拿不到事件 →
        // 由窗口主动驱动 hoverEnter/hoverExit
        if controller.isMiniMode {
            if mouseOverActive != lastMouseOverActiveInMini {
                lastMouseOverActiveInMini = mouseOverActive
                if mouseOverActive {
                    controller.hoverEnter()
                } else {
                    controller.hoverExit()
                }
            }
        } else if lastMouseOverActiveInMini {
            // 退出 mini mode 时重置
            lastMouseOverActiveInMini = false
        }
    }
}
