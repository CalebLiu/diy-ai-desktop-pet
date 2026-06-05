import AppKit
import SwiftUI

class PetWindow: NSWindow {
    let controller: PetController
    private var mouseTrackingTimer: Timer?
    /// Mini mode 下我们自己驱动 hover(SwiftUI .onHover 在屏幕外的 Image 上不会触发)
    private var lastMouseOverActiveInMini: Bool = false
    /// alpha 命中测试用的位图缓存,按 character/baseName 缓存,避免每 100ms 重新解码
    private var bitmapCache: [String: NSBitmapImageRep] = [:]

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
        host.autoresizingMask = [.width, .height]   // mini mode 窗口加宽时内容视图跟随
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
        // 角色在窗口里的水平中心 = 窗口中心 + petXOffset(mini 时锚到贴边一侧)
        let petScreenRect = NSRect(
            x: frame.origin.x + frame.width / 2 + controller.petXOffset - petWidth / 2,
            y: frame.origin.y,
            width: petWidth,
            height: petHeight
        )

        // hot zone 选择:
        //   - 列表已展开 → 整个窗口(避免鼠标移到侧边列表上就关掉)
        //   - Mini 隐藏/探头中 → 仅露出的角色本体(避免加宽窗口产生大片空热区)
        //   - 普通 → 仅角色实际不透明像素(alpha 命中,而非外接矩形)
        let mouseOverActive: Bool
        if controller.showTaskList {
            mouseOverActive = frame.contains(mouseLoc)
        } else if controller.isMiniMode {
            mouseOverActive = petScreenRect.contains(mouseLoc)
        } else {
            mouseOverActive = petScreenRect.contains(mouseLoc)
                && spriteAlphaHit(at: mouseLoc, in: petScreenRect)
        }
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

    /// 鼠标是否压在角色当前帧的不透明像素上(而非外接矩形的透明区)。
    /// 还原 PetView 的绘制几何:aspectRatio(.fit) 居中 + 非 mini 时按 facing 水平翻转。
    private func spriteAlphaHit(at mouseLoc: NSPoint, in rect: NSRect) -> Bool {
        let character = controller.currentCharacter
        let baseName = controller.currentSpriteBaseName
        let key = "\(character)/\(baseName)"

        let rep: NSBitmapImageRep
        if let cached = bitmapCache[key] {
            rep = cached
        } else if let img = SpriteCache.image(character: character, baseName: baseName),
                  let r = (img.representations.compactMap { $0 as? NSBitmapImageRep }.first
                           ?? img.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }) {
            bitmapCache[key] = r
            rep = r
        } else {
            return true   // 拿不到位图就退回矩形命中,别让交互完全失效
        }

        let imgW = CGFloat(rep.pixelsWide)
        let imgH = CGFloat(rep.pixelsHigh)
        guard imgW > 0, imgH > 0 else { return true }

        // aspectRatio(.fit):等比缩放到能放进 petSize,居中,可能有留白
        let scale = min(rect.width / imgW, rect.height / imgH)
        let drawnW = imgW * scale
        let drawnH = imgH * scale
        let offX = (rect.width - drawnW) / 2
        let offY = (rect.height - drawnH) / 2

        // 鼠标相对 rect 的本地坐标(屏幕坐标系 y 向上)
        let ix = (mouseLoc.x - rect.minX) - offX   // 0..drawnW
        let iy = (mouseLoc.y - rect.minY) - offY   // 0..drawnH (y 向上)
        guard ix >= 0, ix <= drawnW, iy >= 0, iy <= drawnH else { return false }

        // 非 mini 时按 facing 水平翻转
        let fx = controller.facing.flipScale < 0 ? (drawnW - ix) : ix
        // 转图像像素坐标(原点左上,y 向下)
        let px = Int(fx / scale)
        let py = Int((drawnH - iy) / scale)
        guard px >= 0, px < rep.pixelsWide, py >= 0, py < rep.pixelsHigh else { return false }

        let alpha = rep.colorAt(x: px, y: py)?.alphaComponent ?? 0
        return alpha > 0.25
    }
}
