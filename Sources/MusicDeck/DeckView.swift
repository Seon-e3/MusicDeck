import SwiftUI

private extension Color {
    init(hex: UInt32) { self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255) }
}

/// 테마별 색. accent는 화면 글씨·눈금·재생 버튼 같은 포인트 색, accentInk는 포인트 버튼 위 아이콘 색.
struct Theme {
    var accent: Color, accentInk: Color
    var shell: [Color], rim: Color, ink: Color, faint: Color, screen: Color
    var knobRing: [Color], knobTop: [Color], pointer: Color, key: Color, keyInk: Color

    static let light = Theme(
        accent: Color(hex: 0xFF5A1F), accentInk: .white,
        shell: [Color(hex: 0xE6E5E1), Color(hex: 0xCFCDC7)], rim: .white.opacity(0.7),
        ink: Color(hex: 0x2A2A2A), faint: Color(hex: 0x8A8883), screen: Color(hex: 0x141414),
        knobRing: [Color(hex: 0xFAFAF8), Color(hex: 0xBDBBB5)], knobTop: [Color(hex: 0xEDECE8), Color(hex: 0xDAD8D2)],
        pointer: Color(hex: 0x2A2A2A), key: Color(hex: 0xF4F3F0), keyInk: Color(hex: 0x2A2A2A))

    // 무광 블랙: 포인트는 흰색, 광택 없이 그라데이션을 아주 약하게, 검정에 회색을 살짝 섞은 톤
    static let matte = Theme(
        accent: Color(hex: 0xF2F0EA), accentInk: Color(hex: 0x1E1E1D),
        shell: [Color(hex: 0x2A2A29), Color(hex: 0x222221)], rim: .white.opacity(0.06),
        ink: Color(hex: 0xD6D4CE), faint: Color(hex: 0x6C6A66), screen: Color(hex: 0x0D0D0D),
        knobRing: [Color(hex: 0x3B3B3A), Color(hex: 0x1D1D1C)], knobTop: [Color(hex: 0x30302F), Color(hex: 0x282827)],
        pointer: Color(hex: 0xE4E2DC), key: Color(hex: 0x353534), keyInk: Color(hex: 0xD6D4CE))
}

extension EnvironmentValues {
    @Entry var theme = Theme.light
}

private func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }

struct DeckView: View {
    @ObservedObject var deck: Deck
    private var t: Theme { deck.theme.palette }

    var body: some View {
        VStack(spacing: 14) {
            header
            display
            if deck.showSources { sourceList }
            HStack(alignment: .top) {
                Knob(label: "MASTER", value: $deck.master,
                     touching: { deck.touching.master = $0 }, changed: deck.setMaster)
                Spacer()
                HStack(spacing: 8) {
                    KeyButton(symbol: "backward.end.fill", action: deck.previous)
                    KeyButton(symbol: "playpause.fill", accent: true, action: deck.togglePlay)
                    KeyButton(symbol: "forward.end.fill", action: deck.next)
                }
                .padding(.top, 18)
                Spacer()
                Knob(label: "SOURCE", value: $deck.sourceVolume,
                     touching: { deck.touching.source = $0 }, changed: deck.setSource)
                    .opacity(deck.track == nil ? 0.4 : 1)
                    .disabled(deck.track == nil)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: t.shell, startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(t.rim, lineWidth: 1))
        )
        // 빈 곳(헤더 글자 포함): 끌면 창이 움직이고, 클릭하면 위치에 따라 숨는다(Deck.tapped 참고).
        // 다이얼·버튼·화면은 자기 동작이 우선한다.
        .onTapGesture { deck.tapped(at: $0) }
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { _ in deck.dragWindow() }
            .onEnded { _ in deck.endDrag() })
        .overlay(alignment: gripAlignment) {
            // 손잡이: 숨은 동안에는 남은 가장자리 전체, 나와 있을 때는 안쪽 가장자리의 작은 줄
            Button(action: deck.toggleStash) {
                let across = (deck.stashed ?? deck.lastSide) == .top    // 위쪽이면 손잡이 줄이 가로
                let lines = ForEach(0..<2, id: \.self) { _ in
                    Capsule().fill(t.faint.opacity(deck.stashed == nil ? 0.5 : 1)).frame(width: across ? 26 : 3, height: across ? 3 : 26)
                }
                Group { if across { VStack(spacing: 3) { lines } } else { HStack(spacing: 3) { lines } } }
                    .padding(across ? .vertical : .horizontal, 7)
                    .frame(maxWidth: deck.stashed != nil ? .infinity : across ? 56 : nil,
                           maxHeight: deck.stashed != nil ? .infinity : across ? nil : 56,
                           alignment: gripAlignment)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(deck.stashed == nil ? "눌러서 숨기기" : "눌러서 꺼내기")
        }
        .contextMenu {
            Button(deck.onTop ? "바탕화면에 두기" : "항상 위에 표시") { deck.onTop.toggle() }
            Toggle("햅틱 진동", isOn: $deck.haptics)
            Picker("테마", selection: $deck.theme) {
                ForEach(ThemeName.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button("종료") { NSApp.terminate(nil) }
        }
        .environment(\.theme, t)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { deck.fit($0) }
        .animation(.easeInOut(duration: 0.25), value: deck.theme)
    }

    private var gripAlignment: Alignment {
        switch deck.stashed ?? deck.lastSide {
        case .left: .trailing
        case .right: .leading
        case .top: .bottom
        }
    }

    private func elapsed(_ tr: Track, at date: Date) -> Double {
        min(tr.duration > 0 ? tr.duration : .infinity, tr.position + (tr.playing ? date.timeIntervalSince(deck.polledAt) : 0))
    }

    private func clock(_ sec: Double) -> String {
        let s = Int(sec)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 커버: 유튜브 썸네일 또는 애플뮤직 앨범 커버. 없으면 음표 아이콘
    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(t.accent.opacity(0.08))
            if let img = deck.artwork {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 16)).foregroundStyle(t.accent.opacity(0.4))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(deck.track?.playing == true ? t.accent : t.faint.opacity(0.5)).frame(width: 7, height: 7)
            Text("MUSICDECK").font(mono(10, .bold)).tracking(2.5)
            Spacer()
            if deck.sources.count >= 2 {
                // 노션 토글처럼 ▸를 누르면 아래로 소스 목록이 펼쳐진다
                Button { withAnimation(.easeOut(duration: 0.18)) { deck.showSources.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(deck.showSources ? 90 : 0))
                        Text("SOURCES \(deck.sources.count)").font(mono(10))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("재생할 곳 고르기")
            } else {
                Text("MD-1").font(mono(10))
            }
        }
        .foregroundStyle(t.ink)
    }

    private var sourceList: some View {
        VStack(spacing: 0) {
            ForEach(deck.sources, id: \.key) { s in
                let current = s.key == deck.track?.key
                Button { deck.choose(s) } label: {
                    HStack(spacing: 8) {
                        Text(s.player == .music ? "MUSIC" : s.player == .chrome ? "CHROME" : "SAFARI")
                            .font(mono(9)).foregroundStyle(t.accent.opacity(0.5))
                            .frame(width: 44, alignment: .leading)
                        Text(s.title).font(mono(11, current ? .bold : .regular)).lineLimit(1)
                        Spacer(minLength: 4)
                        if s.playing { Text("▶").font(mono(9)) }
                    }
                    .foregroundStyle(t.accent.opacity(current ? 1 : 0.7))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if s.key != deck.sources.last?.key { Rectangle().fill(t.accent.opacity(0.08)).frame(height: 1) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(t.screen))
        .transition(.opacity)
    }

    private var display: some View {
        Button(action: deck.focus) {
            HStack(spacing: 10) {
                artwork
                // 0.5초마다 다시 그려서 재생 시간과 진행 막대가 흐르게 한다
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let now = deck.track.map { elapsed($0, at: ctx.date) } ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(deck.track?.label ?? "NO SOURCE")
                            Spacer()
                            if let tr = deck.track {
                                Text((tr.playing ? "▶ " : "❚❚ ") + (tr.duration > 0 ? "\(clock(now)) / \(clock(tr.duration))" : tr.playing ? "PLAY" : "PAUSE"))
                            }
                        }
                        .font(mono(10))
                        .foregroundStyle(t.accent.opacity(0.65))

                        Text(deck.track?.title ?? deck.hint ?? "유튜브나 애플뮤직을 틀어보세요")
                            .font(mono(deck.track == nil ? 11 : 13, .medium))
                            .foregroundStyle(t.accent)
                            .lineLimit(deck.track == nil ? 2 : 1)
                            .truncationMode(.tail)

                        if let tr = deck.track, tr.duration > 0 {
                            Capsule().fill(t.accent)
                                .scaleEffect(x: now / tr.duration, anchor: .leading)
                                .background(Capsule().fill(t.accent.opacity(0.18)))
                                .frame(height: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(t.screen)
                .shadow(color: .black.opacity(0.35), radius: 1, y: -1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("눌러서 재생 중인 탭/앱으로 이동")
    }
}

/// 스크롤 이벤트는 SwiftUI 뷰로 직접 오지 않아서, 앱 전체 스크롤을 엿보다가 포인터가 노브 위에 있을 때만 반응한다.
/// 비활성 창에서는 onHover가 안 올 수 있어서 노브 위치를 직접 기억해 비교한다.
private final class ScrollTap {
    var frame = CGRect.zero       // 창 안에서 노브 위치(SwiftUI 좌표: 왼쪽 위 원점)
    var enabled = true
    var leftover: CGFloat = 0     // 한 칸(2)이 안 되는 스크롤 양을 모아둔다
    var monitor: Any?
}

/// 노브 둘레를 따라 원을 그리며 돌리는 노브. 시계 방향이면 커진다. 2 단위로 한 칸씩 딸깍.
/// 포인터를 올리고 스크롤해도 돌아간다(위로·오른쪽으로 쓸면 커짐).
struct Knob: View {
    let label: String
    @Binding var value: Double
    let touching: (Bool) -> Void
    let changed: (Int) -> Void
    @State private var drag: (raw: Double, angle: Double)?   // 드래그 중 누적값, 직전 포인터 각도
    @Environment(\.theme) private var t
    @Environment(\.isEnabled) private var isEnabled
    @State private var scroll = ScrollTap()

    private var angle: Angle { .degrees(-135 + value / 100 * 270) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(0..<11) { i in
                    Capsule()
                        .fill(Double(i * 10) <= value ? t.accent : t.faint.opacity(0.45))
                        .frame(width: 2, height: 5)
                        .offset(y: -36)
                        .rotationEffect(.degrees(-135 + Double(i) * 27))
                }
                Circle()
                    .fill(LinearGradient(colors: t.knobRing, startPoint: .top, endPoint: .bottom))
                    .frame(width: 54, height: 54)
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
                Circle()
                    .fill(LinearGradient(colors: t.knobTop, startPoint: .top, endPoint: .bottom))
                    .frame(width: 44, height: 44)
                Capsule().fill(t.pointer).frame(width: 3, height: 13).offset(y: -14).rotationEffect(angle)
            }
            .frame(width: 80, height: 80)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let dx = g.location.x - 40, dy = g.location.y - 40   // 노브 중심 기준
                        guard dx * dx + dy * dy > 64 else { return }        // 중심 근처는 각도가 튀므로 무시
                        let a = atan2(dy, dx) * 180 / .pi                  // 화면 좌표라 시계 방향이 +
                        guard let d = drag else { drag = (value, a); touching(true); return }
                        var delta = a - d.angle
                        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
                        let raw = min(max(d.raw + delta / 270 * 100, 0), 100)
                        drag = (raw, a)
                        let stepped = (raw / 2).rounded() * 2
                        guard stepped != value else { return }
                        value = stepped
                        Click.detent()
                        changed(Int(stepped))
                    }
                    .onEnded { _ in drag = nil; touching(false) }
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { scroll.frame = $0 }
            .onChange(of: isEnabled, initial: true) { scroll.enabled = isEnabled }
            .onAppear {
                scroll.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
                    guard scroll.enabled, let h = e.window?.contentView?.bounds.height,
                          scroll.frame.contains(CGPoint(x: e.locationInWindow.x, y: h - e.locationInWindow.y)) else { return e }
                    scrolled(e)
                    return nil
                }
            }
            .onDisappear { scroll.monitor.map(NSEvent.removeMonitor) }

            Text("\(label) \(String(format: "%03d", Int(value)))")
                .font(mono(9, .medium)).tracking(1)
                .foregroundStyle(t.ink)
        }
    }
}

extension Knob {
    /// 손가락 방향 기준으로 위·오른쪽이면 커진다. '자연스러운 스크롤' 설정과 상관없이 같은 방향.
    private func scrolled(_ e: NSEvent) {
        let flip: CGFloat = e.isDirectionInvertedFromDevice ? -1 : 1
        let amount = (e.scrollingDeltaY - e.scrollingDeltaX) * flip * (e.hasPreciseScrollingDeltas ? 0.25 : 2)
        scroll.leftover += amount
        let steps = (scroll.leftover / 2).rounded(.towardZero)
        guard steps != 0 else { return }
        scroll.leftover -= steps * 2
        let next = min(max(value + steps * 2, 0), 100)
        guard next != value else { return }
        value = next
        Click.detent()
        changed(Int(next))
    }
}

struct KeyButton: View {
    let symbol: String
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13, weight: .bold)) }
            .buttonStyle(KeyStyle(accent: accent))
    }
}

private struct KeyStyle: ButtonStyle {
    let accent: Bool
    @Environment(\.theme) private var t

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .foregroundStyle(accent ? t.accentInk : t.keyInk)
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(accent ? t.accent : t.key)
                .shadow(color: .black.opacity(down ? 0.15 : 0.3), radius: down ? 0.5 : 2, y: down ? 0.5 : 2))
            .offset(y: down ? 1.5 : 0)
            .animation(.easeOut(duration: 0.06), value: down)
            .onChange(of: down) { _, isDown in if isDown { Click.press() } }
    }
}
