import AppKit

/// Sprite 缓存,按 (character, baseName) 查找
/// 优先级:
///   1. ~/Library/Application Support/DeskPet/characters/<character>/<baseName>.png
///   2. Bundle 里的 <character>_<baseName>.png
enum SpriteCache {
    private static var cache: [String: NSImage] = [:]

    static func image(character: String, baseName: String) -> NSImage? {
        let key = "\(character)/\(baseName)"
        if let cached = cache[key] { return cached }

        guard let url = resolveURL(character: character, baseName: baseName),
              let img = NSImage(contentsOf: url) else {
            return nil
        }
        cache[key] = img
        return img
    }

    private static func resolveURL(character: String, baseName: String) -> URL? {
        // 优先磁盘
        let onDiskURL = CharacterRegistry.charactersDir
            .appendingPathComponent(character, isDirectory: true)
            .appendingPathComponent("\(baseName).png")
        if FileManager.default.fileExists(atPath: onDiskURL.path) {
            return onDiskURL
        }
        // Fallback: bundled. The .app build stores images in Bundle.main;
        // `swift run` stores them in SwiftPM's Bundle.module.
        let resourceName = "\(character)_\(baseName)"
        return Bundle.main.url(forResource: resourceName, withExtension: "png")
            ?? Bundle.module.url(forResource: resourceName, withExtension: "png")
    }

    /// 切换角色时清缓存,强制重读
    static func invalidate() {
        cache.removeAll()
    }
}
