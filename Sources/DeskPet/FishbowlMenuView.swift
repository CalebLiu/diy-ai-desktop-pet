import SwiftUI
import AppKit

struct FishbowlMenuView: View {
    @ObservedObject var launcher: FishbowlLauncher
    let onPick: (FishbowlSite) -> Void

    @State private var editing = false
    @State private var showAddForm = false
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newEmoji = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Lang.t("摸鱼一下 🐟", "Slack off 🐟"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.5))
                Spacer()
                Button(editing ? Lang.t("完成", "Done") : Lang.t("编辑", "Edit")) {
                    editing.toggle()
                    if !editing { showAddForm = false }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(launcher.sites) { site in
                FishbowlSiteRow(
                    site: site,
                    editing: editing,
                    onTap: { onPick(site) },
                    onDelete: { launcher.removeSite(id: site.id) }
                )
            }

            if editing {
                if showAddForm {
                    addForm
                } else {
                    Button(action: {
                        showAddForm = true
                        // accessory app + 非 key 窗口,不激活的话 popover 文本框打不了字
                        NSApp.activate(ignoringOtherApps: true)
                    }) {
                        HStack(spacing: 10) {
                            Text("➕").font(.system(size: 16))
                            Text(Lang.t("添加站点", "Add site")).font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }
            }

            Divider()
                .padding(.horizontal, 10)
                .padding(.top, 4)

            Text(editing
                 ? Lang.t("点 ✕ 删除 · 输入网址即可,自动补 https", "Tap ✕ to delete · URL auto-prefixes https")
                 : Lang.t("⌘⌥M 呼出 · 点「编辑」增删站点", "⌘⌥M to toggle · tap Edit to add/remove"))
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.55))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 220)
        .padding(.bottom, 4)
    }

    private var addForm: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("🐟", text: $newEmoji)
                    .frame(width: 34)
                    .multilineTextAlignment(.center)
                TextField(Lang.t("名称", "Name"), text: $newName)
            }
            TextField(Lang.t("网址 (如 douyin.com)", "URL (e.g. reddit.com)"), text: $newURL)
                .onSubmit(commitAdd)
            HStack(spacing: 8) {
                Spacer()
                Button(Lang.t("取消", "Cancel")) { resetForm() }
                    .buttonStyle(.plain)
                    .foregroundColor(Color(white: 0.5))
                Button(Lang.t("添加", "Add"), action: commitAdd)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                              || newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.system(size: 11))
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func commitAdd() {
        if launcher.addSite(name: newName, url: newURL, emoji: newEmoji) {
            resetForm()
        }
    }

    private func resetForm() {
        newName = ""; newURL = ""; newEmoji = ""
        showAddForm = false
    }
}

private struct FishbowlSiteRow: View {
    let site: FishbowlSite
    var editing: Bool = false
    let onTap: () -> Void
    var onDelete: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if editing {
                Button(action: onDelete) {
                    Text("✕")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
            }
            Text(site.emoji).font(.system(size: 18))
            Text(site.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && !editing ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !editing { onTap() } }
    }
}
