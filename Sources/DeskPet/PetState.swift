import Foundation
import AppKit
import ApplicationServices

enum PetState: String {
    case idle
    case walking
    case resting
    case thinking
    case done

    /// 帧序列(只返回 base name,不含角色前缀)。
    /// 实际加载由 SpriteCache 加上 currentCharacter 拼路径。
    var frames: [String] {
        switch self {
        case .idle:
            return ["idle"]
        case .walking:
            return ["walk_a", "walk_mid", "walk_b"]
        case .resting:
            return ["resting"]
        case .thinking:
            return ["thinking_a", "thinking_ab", "thinking_b", "thinking_bc", "thinking_c"]
        case .done:
            return ["done_a", "done_b"]
        }
    }

    var fps: Double {
        switch self {
        case .walking: return 4.0
        case .thinking: return 3.5
        case .done: return 3.0
        default: return 1.0
        }
    }

    var canBeInterrupted: Bool {
        switch self {
        case .idle, .walking, .resting: return true
        case .thinking, .done: return false
        }
    }
}

/// 一个 agent 会话(由窗口/外部 session id 标识,首条 prompt 当标签)
struct PetSession: Identifiable, Equatable {
    let id: String
    var label: String
    var source: String
    var app: NSRunningApplication
    var window: AXUIElement?
    var lastActivity: Date
    var externalSessionId: String?
    var isDone: Bool = false

    static func == (lhs: PetSession, rhs: PetSession) -> Bool {
        return lhs.id == rhs.id
    }
}

enum Direction {
    case left
    case right

    var flipScale: CGFloat {
        switch self {
        case .left: return -1
        case .right: return 1
        }
    }
}
