import Foundation

/// 极简本地化:按系统首选语言在中/英之间切,允许用户在菜单里手动覆盖(持久化到 UserDefaults)。
/// 用法:`Lang.t("中文", "English")`。
enum Lang {
    /// 手动覆盖:nil = 跟随系统,"zh" / "en" = 强制。
    private static let defaultsKey = "preferredLanguageOverride"

    static var override: String? {
        get { UserDefaults.standard.string(forKey: defaultsKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
        }
    }

    /// 当前是否走英文。优先看手动覆盖,否则看系统首选语言(非 zh 即英文)。
    static var isEnglish: Bool {
        if let o = override { return o == "en" }
        let code = (Locale.preferredLanguages.first ?? "en").prefix(2).lowercased()
        return code != "zh"
    }

    static func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }
}
