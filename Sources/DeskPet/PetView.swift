import SwiftUI
import AppKit

struct PetView: View {
    @ObservedObject var controller: PetController

    @State private var breathScaleY: CGFloat = 1.0
    @State private var walkBobY: CGFloat = 0
    @State private var tapBounce: CGFloat = 1.0
    @State private var dragActive: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 角色(没生成角色时显示占位提示)
            petSprite
                .scaleEffect(tapBounce)
                .offset(y: walkBobY)
                // Mini mode 下不翻转,让 peek_<edge> sprite 按原画呈现;否则跟随 facing
                .scaleEffect(x: controller.isMiniMode ? 1 : controller.facing.flipScale, y: 1)
                .scaleEffect(CGSize(width: 1.0, height: breathScaleY), anchor: .bottom)
                .onTapGesture { handleTap() }
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { _ in
                            if !dragActive {
                                dragActive = true
                                controller.startDrag()
                            }
                            // 拖拽实际由 60fps timer 接管,这里不处理 translation
                        }
                        .onEnded { _ in
                            if dragActive {
                                dragActive = false
                                controller.endDrag()
                            }
                        }
                )
                .onHover { hovering in
                    if hovering { controller.hoverEnter() } else { controller.hoverExit() }
                }

            // hover 时显示 task 列表(优先级最高)
            if controller.showTaskList && !controller.sessions.isEmpty {
                TaskListView(
                    sessions: controller.sessions,
                    onSelect: { controller.activateSession($0) }
                )
                .frame(maxWidth: controller.windowSize.width - 16)
                .offset(y: -(controller.petSize.height + 4))
                .onHover { hovering in
                    if hovering { controller.hoverEnter() } else { controller.hoverExit() }
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            // 普通气泡(列表没显示时才显示)
            else if let bubble = controller.taskBubbleText {
                TaskBubble(text: bubble)
                    .frame(maxWidth: controller.windowSize.width - 20)
                    .offset(y: -(controller.petSize.height + 4))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: controller.windowSize.width, height: controller.windowSize.height, alignment: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: controller.taskBubbleText)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: controller.showTaskList)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                breathScaleY = 1.012
            }
        }
        .onChange(of: controller.state) { newState in
            if newState == .walking {
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
                    walkBobY = -3
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    walkBobY = 0
                }
            }
        }
    }

    /// 有 sprite → 显示角色;没有(还没生成角色)→ 显示占位提示。
    @ViewBuilder private var petSprite: some View {
        if let img = SpriteCache.image(character: controller.currentCharacter,
                                       baseName: controller.currentSpriteBaseName) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: controller.petSize.width, height: controller.petSize.height)
        } else {
            PlaceholderPet()
                .frame(width: controller.petSize.width, height: controller.petSize.height)
        }
    }

    private func handleTap() {
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { tapBounce = 0.88 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { tapBounce = 1.0 }
        }
        controller.handlePetTap()
    }
}

/// 还没生成任何角色时的占位:提示用户去 README 用 pipeline 生成。
struct PlaceholderPet: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("🐾")
                .font(.system(size: 40))
            Text(Lang.t("还没有角色", "No character yet"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(white: 0.25))
            Text(Lang.t("用 tools/ 里的 pipeline\n生成一个(见 README)",
                        "Generate one with the\npipeline in tools/ (see README)"))
                .font(.system(size: 9))
                .multilineTextAlignment(.center)
                .foregroundColor(Color(white: 0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.92))
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
        )
    }
}

/// Task 列表(hover 时出现)
struct TaskListView: View {
    let sessions: [PetSession]
    let onSelect: (PetSession) -> Void

    private var groupedSessions: [(source: String, sessions: [PetSession])] {
        let groups = Dictionary(grouping: sessions, by: \.source)
        return groups.keys.sorted { lhs, rhs in
            if lhs == "Codex" { return true }
            if rhs == "Codex" { return false }
            if lhs == "Claude" { return true }
            if rhs == "Claude" { return false }
            return lhs < rhs
        }.compactMap { source in
            guard let sourceSessions = groups[source] else { return nil }
            return (source, sourceSessions)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(groupedSessions, id: \.source) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.source) · \(group.sessions.count) task\(group.sessions.count > 1 ? "s" : "")")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(white: 0.45))
                        .padding(.horizontal, 8)
                        .padding(.top, group.source == groupedSessions.first?.source ? 6 : 2)
                        .padding(.bottom, 2)

                    ForEach(group.sessions) { session in
                        SessionRow(session: session, showsSource: groupedSessions.count > 1, onTap: { onSelect(session) })
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
        )
    }
}

struct SessionRow: View {
    let session: PetSession
    let showsSource: Bool
    let onTap: () -> Void
    @State private var hovering = false

    private var dotColor: Color {
        session.isDone ? Color(red: 0.30, green: 0.78, blue: 0.42)  // 完成:绿
                       : Color(red: 0.98, green: 0.62, blue: 0.20)  // 运行中:橙
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                Text(session.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.15))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if showsSource {
                    Text(session.source)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(white: 0.55))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color(white: 0.93) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 头顶任务气泡(短临时提示)
struct TaskBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.15))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                )
            BubbleTail()
                .fill(Color.white)
                .frame(width: 10, height: 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
