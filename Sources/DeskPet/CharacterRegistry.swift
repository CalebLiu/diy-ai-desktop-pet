import Foundation
import AppKit

/// 角色发现 + meta 查找(优先 ~/Library 里的 meta.json,fallback 硬编码 map)
enum CharacterRegistry {

    /// 用户角色库路径:~/Library/Application Support/DeskPet/characters/
    static var charactersDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("DeskPet/characters", isDirectory: true)
    }

    // MARK: - 硬编码 fallback(角色没 meta.json 时用)
    // 公共版不内置任何角色:display name 回退到 slug 首字母大写,音效回退到 "Hero"。
    // 你生成的角色会带 meta.json(由 profile 复制而来),自动覆盖这些回退值。
    private static let displayNames: [String: String] = [:]

    private static let doneSounds: [String: String] = [:]

    // MARK: - meta.json 读取(缓存,避免每次 done 都打 IO)
    private static var metaCache: [String: [String: Any]] = [:]

    private static func meta(for slug: String) -> [String: Any]? {
        if let cached = metaCache[slug] { return cached }
        let path = charactersDir.appendingPathComponent(slug).appendingPathComponent("meta.json")
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        metaCache[slug] = obj
        return obj
    }

    /// 切换/重装角色时调一次,清掉缓存
    static func invalidateMetaCache() {
        metaCache.removeAll()
    }

    // MARK: - 对外 API
    static func displayName(for slug: String) -> String {
        if let m = meta(for: slug), let name = m["display_name"] as? String, !name.isEmpty {
            return name
        }
        return displayNames[slug] ?? slug.capitalized
    }

    static func doneSoundName(for slug: String) -> String {
        if let m = meta(for: slug), let sound = m["done_sound"] as? String, !sound.isEmpty {
            return sound
        }
        return doneSounds[slug] ?? "Hero"
    }

    // MARK: - 角色发现(逻辑不变)
    static func bundledSlugs() -> [String] {
        let resourceURLs = [Bundle.main.resourceURL, Bundle.module.resourceURL].compactMap { $0 }
        let slugs = resourceURLs.reduce(into: Set<String>()) { result, resourceURL in
            guard let files = try? FileManager.default.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) else { return }
            for url in files {
                let name = url.deletingPathExtension().lastPathComponent
                guard name.hasSuffix("_idle") else { continue }
                result.insert(String(name.dropLast("_idle".count)))
            }
        }
        return Array(slugs).sorted()
    }

    static func onDiskSlugs() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: charactersDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        return entries.compactMap { url -> String? in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue else { return nil }
            let idlePath = url.appendingPathComponent("idle.png").path
            guard FileManager.default.fileExists(atPath: idlePath) else { return nil }
            return url.lastPathComponent
        }.sorted()
    }

    static func allSlugs() -> [String] {
        let combined = Set(bundledSlugs()).union(onDiskSlugs())
        return Array(combined).sorted()
    }
}
