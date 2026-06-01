import Foundation
import AppKit
import Combine

struct FishbowlSite: Codable, Identifiable, Equatable {
    let id: String      // slug, e.g. "douyin"
    let name: String    // 显示名
    let url: String     // 打开的网址
    let emoji: String   // 简易图标
}

/// 摸鱼站点 launcher：读 ~/.config/deskpet/fishbowl.json，
/// 用独立 Chrome profile (~/Library/Application Support/DeskPet/fishbowl) 开新窗口。
final class FishbowlLauncher: ObservableObject {
    static let shared = FishbowlLauncher()

    @Published private(set) var sites: [FishbowlSite] = []

    private let configPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("deskpet")
            .appendingPathComponent("fishbowl.json")
    }()

    private let profilePath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("DeskPet")
            .appendingPathComponent("fishbowl")
    }()

    private init() {
        loadOrCreateConfig()
        ensureProfileDir()
    }

    func reload() {
        loadOrCreateConfig()
    }

    /// 添加一个摸鱼站点(应用内增加)。url 缺协议头自动补 https://,emoji 空给默认。
    /// 返回 false 表示输入不合法(名字或网址为空)。
    @discardableResult
    func addSite(name: String, url rawURL: String, emoji rawEmoji: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return false }
        if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
            url = "https://" + url
        }
        let emoji = rawEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "🐟" : rawEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let site = FishbowlSite(id: UUID().uuidString, name: name, url: url, emoji: emoji)
        sites.append(site)
        writeConfig(sites)
        return true
    }

    /// 删除一个站点。
    func removeSite(id: String) {
        sites.removeAll { $0.id == id }
        writeConfig(sites)
    }

    private func loadOrCreateConfig() {
        let fm = FileManager.default
        let dir = configPath.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: configPath.path) {
            sites = Self.defaultSites
            writeConfig(sites)
            return
        }

        do {
            let data = try Data(contentsOf: configPath)
            sites = try JSONDecoder().decode([FishbowlSite].self, from: data)
            if sites.isEmpty { sites = Self.defaultSites }
        } catch {
            NSLog("Fishbowl: 配置读取失败,用默认值: \(error)")
            sites = Self.defaultSites
        }
    }

    private func writeConfig(_ sites: [FishbowlSite]) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(sites)
            try data.write(to: configPath, options: .atomic)
        } catch {
            NSLog("Fishbowl: 配置写入失败: \(error)")
        }
    }

    private func ensureProfileDir() {
        try? FileManager.default.createDirectory(at: profilePath, withIntermediateDirectories: true)
    }

    /// 用独立 Chrome profile 打开 URL,复用同一个摸鱼窗口只新增标签页。
    ///
    /// 关键:直接 exec Chrome 二进制(不用 `open -n`)。Chrome 靠 user-data-dir 里的
    /// SingletonLock 识别实例 —— 摸鱼 profile 第一次启动新建窗口,之后每次点击会把
    /// URL 转发给已在跑的摸鱼实例,在当前窗口里开成新标签页(不带 `--new-window`),
    /// 不再堆窗口。跟工作 Chrome 仍因 user-data-dir 不同而完全隔离。
    func openSite(_ site: FishbowlSite) {
        guard let chromeBin = Self.chromeBinaryURL() else {
            NSLog("Fishbowl: 找不到 Google Chrome,请确认已安装。")
            return
        }
        let task = Process()
        task.executableURL = chromeBin
        task.arguments = [
            "--user-data-dir=\(profilePath.path)",
            site.url
        ]
        do {
            try task.run()
        } catch {
            NSLog("Fishbowl: 启动 Chrome 失败: \(error)。请确认已安装 Google Chrome。")
        }
    }

    /// 解析 Chrome 可执行二进制路径(不是 .app)。
    private static func chromeBinaryURL() -> URL? {
        let fm = FileManager.default
        var appPath: String?
        let candidates = [
            "/Applications/Google Chrome.app",
            "\(NSHomeDirectory())/Applications/Google Chrome.app",
        ]
        for c in candidates where fm.fileExists(atPath: c) {
            appPath = c
            break
        }
        if appPath == nil {
            appPath = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: "com.google.Chrome")?.path
        }
        guard let appPath else { return nil }
        return URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/MacOS/Google Chrome")
    }

    /// 默认站点按系统语言切:中文给国内站,英文给海外站。首次运行时写进 fishbowl.json。
    static var defaultSites: [FishbowlSite] {
        if Lang.isEnglish {
            return [
                FishbowlSite(id: "youtube", name: "YouTube", url: "https://www.youtube.com", emoji: "▶️"),
                FishbowlSite(id: "reddit",  name: "Reddit",  url: "https://www.reddit.com",  emoji: "👽"),
                FishbowlSite(id: "x",       name: "X",       url: "https://www.x.com",       emoji: "🐦"),
                FishbowlSite(id: "twitch",  name: "Twitch",  url: "https://www.twitch.tv",   emoji: "🎮"),
            ]
        }
        return [
            FishbowlSite(id: "douyin",   name: "抖音",     url: "https://www.douyin.com",       emoji: "🎵"),
            FishbowlSite(id: "bilibili", name: "B站",      url: "https://www.bilibili.com",     emoji: "📺"),
            FishbowlSite(id: "xhs",      name: "小红书",   url: "https://www.xiaohongshu.com",  emoji: "📕"),
            FishbowlSite(id: "youtube",  name: "YouTube",  url: "https://www.youtube.com",      emoji: "▶️"),
        ]
    }
}
