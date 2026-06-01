import Foundation
import AppKit
import IOKit.ps

enum SystemMonitor {

    /// 当前电池百分比 (0-100),没有电池(台式机)返回 nil
    static func batteryPercentage() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let current = info[kIOPSCurrentCapacityKey] as? Int,
               let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 {
                return Int((Double(current) / Double(max)) * 100)
            }
        }
        return nil
    }

    /// 从最近一次输入事件到现在的秒数(键鼠滚轮中最近的那个)
    static func idleSeconds() -> TimeInterval {
        let types: [CGEventType] = [.leftMouseDown, .rightMouseDown, .mouseMoved, .keyDown, .scrollWheel]
        let values = types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }
        return values.min() ?? 0
    }

    /// 当前小时(0-23,本地时区)
    static func currentHour() -> Int {
        return Calendar.current.component(.hour, from: Date())
    }

    /// 凌晨 0-6 点 或 深夜 23 点之后
    static func isDeepNight() -> Bool {
        let h = currentHour()
        return h < 6 || h >= 23
    }
}
