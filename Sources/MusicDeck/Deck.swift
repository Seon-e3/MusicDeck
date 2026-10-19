import AppKit

enum Player: String {
    case chrome = "Google Chrome", safari = "Safari", music = "Music"

    var bundleID: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .safari: "com.apple.Safari"
        case .music: "com.apple.Music"
        }
    }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
}

enum ThemeName: String, CaseIterable {
    case light, matte
    var title: String { self == .light ? "라이트" : "무광 블랙" }
    var palette: Theme { self == .light ? .light : .matte }
}

struct Track: Equatable {
    let player: Player
    let window: Int, tab: Int          // 브라우저 탭 위치. 애플뮤직은 0
    var playing: Bool
    var volume: Int
    var position: Double, duration: Double   // 초. 길이를 모르면(라이브 등) duration 0
    var title: String
    var artID: String                  // 커버를 찾는 키: 유튜브 영상 ID, 애플뮤직 곡 ID
    var key: String { "\(player.rawValue)#\(window)#\(tab)" }

    var label: String {
        switch player {
        case .chrome: "CHROME · YOUTUBE"
        case .safari: "SAFARI · YOUTUBE"
        case .music: "APPLE MUSIC"
        }
    }
}

/// AppleScript는 전부 이 큐 하나에서만 실행한다(NSAppleScript는 스레드 안전하지 않음).
private let scriptQueue = DispatchQueue(label: "musicdeck.script")

/// 결과 문자열, 실패 시 에러 메시지
private func runScript(_ source: String) -> (String?, String?) {
    var err: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
    return (result?.stringValue, err?[NSAppleScript.errorMessage] as? String)
}

// 유튜브 탭 안에서 실행하는 JS. AppleScript 문자열 안에 들어가므로 큰따옴표·역슬래시 금지.
private let jsPlayer = "var p=document.getElementById('movie_player'),v=document.querySelector('video');"
private let jsRead = "(function(){\(jsPlayer)if(!v)return '';var vol=p&&p.getVolume?p.getVolume():Math.round(v.volume*100);var d=p&&p.getVideoData?p.getVideoData():{};return (v.paused?'0':'1')+'|'+vol+'|'+Math.floor(v.currentTime)+'|'+(isFinite(v.duration)?Math.floor(v.duration):0)+'|'+(d.video_id||'')+'|'+(d.title||document.title);})()"
private func jsSetVolume(_ n: Int) -> String { "(function(){\(jsPlayer)if(p&&p.setVolume){p.setVolume(\(n));if(p.unMute)p.unMute();}else if(v){v.volume=\(n)/100;}})()" }
private let jsPlay = "(function(){\(jsPlayer)if(v&&v.paused)v.play();})()"
private let jsPause = "(function(){\(jsPlayer)if(v&&!v.paused)v.pause();})()"
private let jsToggle = "(function(){\(jsPlayer)if(v){v.paused?v.play():v.pause();}})()"
private let jsPrev = "(function(){\(jsPlayer)var b=document.querySelector('ytmusic-player-bar .previous-button')||document.querySelector('.ytp-prev-button');if(b&&b.offsetParent!==null)b.click();else if(v)v.currentTime=0;})()"
private let jsNext = "(function(){var b=document.querySelector('ytmusic-player-bar .next-button')||document.querySelector('.ytp-next-button');if(b)b.click();})()"

/// 크롬·사파리의 모든 유튜브 탭 상태를 한 번에 읽는 스크립트. 줄마다 "창,탭|재생|볼륨|제목", 실패한 탭은 "!메시지"
private func browserScanScript(_ p: Player) -> String {
    let exec = p == .chrome
        ? "execute tab t of window w javascript \"\(jsRead)\""
        : "do JavaScript \"\(jsRead)\" in tab t of window w"
    return """
    set out to ""
    tell application "\(p.rawValue)"
      repeat with w from 1 to count windows
        try
          repeat with t from 1 to count tabs of window w
            set u to URL of tab t of window w
            if u contains "youtube.com/watch" or u contains "music.youtube.com" then
              try
                set r to \(exec)
                if r is not missing value and r is not "" then set out to out & w & "," & t & "|" & r & linefeed
              on error m
                set out to out & "!" & m & linefeed
              end try
            end if
          end repeat
        end try
      end repeat
    end tell
    return out
    """
}

private func scanBrowser(_ p: Player) -> (tracks: [Track], error: String?) {
    guard p.isRunning else { return ([], nil) }
    let (out, err) = runScript(browserScanScript(p))
    var tracks: [Track] = [], error = err
    for line in (out ?? "").split(separator: "\n") {
        if line.hasPrefix("!") { error = String(line.dropFirst()); continue }
        let f = line.split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false)
        let pos = f[0].split(separator: ",").compactMap { Int($0) }
        guard f.count == 7, pos.count == 2 else { continue }
        tracks.append(Track(player: p, window: pos[0], tab: pos[1], playing: f[1] == "1",
                            volume: Int(f[2]) ?? 100, position: Double(f[3]) ?? 0, duration: Double(f[4]) ?? 0,
                            title: String(f[6]), artID: String(f[5])))
    }
    return (tracks, error)
}

private func scanMusic() -> Track? {
    guard Player.music.isRunning else { return nil }
    let (out, _) = runScript("""
    tell application "Music"
      set s to player state as string
      if s is not "playing" and s is not "paused" then return ""
      set d to 0
      try
        set d to duration of current track as integer
      end try
      return s & "|" & sound volume & "|" & (player position as integer) & "|" & d & "|" & persistent ID of current track & "|" & name of current track & " — " & artist of current track
    end tell
    """)
    let f = (out ?? "").split(separator: "|", maxSplits: 5)
    guard f.count == 6 else { return nil }
    return Track(player: .music, window: 0, tab: 0, playing: f[0] == "playing",
                 volume: Int(f[1]) ?? 100, position: Double(f[2]) ?? 0, duration: Double(f[3]) ?? 0,
                 title: String(f[5]), artID: String(f[4]))
}

/// 스크립트 큐에서 호출
private func send(_ t: Track, music: String, js: String) {
    if t.player == .music { _ = runScript("tell application \"Music\" to \(music)") }
    else { browserJS(t, js) }
}

private func browserJS(_ t: Track, _ js: String) {
    let target = "tab \(t.tab) of window \(t.window)"
    _ = runScript(t.player == .chrome
        ? "tell application \"Google Chrome\" to execute \(target) javascript \"\(js)\""
        : "tell application \"Safari\" to do JavaScript \"\(js)\" in \(target)")
}

/// 값이 빠르게 바뀔 때(다이얼 드래그) 밀린 값은 버리고 가장 최근 값만 적용한다. main 스레드에서 호출.
final class Latest {
    private var want = 0, busy = false
    private let apply: (Int) -> Void
    init(_ apply: @escaping (Int) -> Void) { self.apply = apply }

    func set(_ v: Int) {
        want = v
        guard !busy else { return }
        busy = true
        scriptQueue.async {
            var last = Int.min
            while true {
                let next: Int? = DispatchQueue.main.sync {
                    if self.want == last { self.busy = false; return nil }
                    return self.want
                }
                guard let next else { return }
                self.apply(next)
                last = next
            }
        }
    }
}

final class Deck: ObservableObject {
    @Published var track: Track?
    @Published var master: Double = 50
    @Published var sourceVolume: Double = 50
    @Published var hint: String?
    @Published var theme = ThemeName(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .light {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    @Published var artwork: NSImage?
    private(set) var polledAt = Date()   // track.position을 읽은 시각. 진행 막대는 이 시각부터 흐른 만큼 더한다
    private var artID = ""
    @Published var haptics = Click.haptics { didSet { Click.haptics = haptics } }
    @Published var onTop = false { didSet { window?.level = onTop ? .floating : Deck.desktopLevel } }

    static let desktopLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    weak var window: NSWindow?

    // 다이얼을 만지는 중이거나 막 놓았을 때는 폴링 값으로 덮어쓰지 않는다
    var touching = (master: false, source: false)
    private var holdUntil = (master: Date.distantPast, source: Date.distantPast)
    private var scanning = false

    private lazy var masterWriter = Latest { _ = runScript("set volume output volume \($0)") }
    private lazy var sourceWriter = Latest { [weak self] v in
        guard let t = DispatchQueue.main.sync(execute: { self?.track }) else { return }
        if t.player == .music { _ = runScript("tell application \"Music\" to set sound volume to \(v)") }
        else { browserJS(t, jsSetVolume(v)) }
    }

    func start() {
        if let screen = window?.screen { stashIfPastEdge(of: screen) }   // 숨긴 채로 종료했으면 그대로 복원
        poll()
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        guard !scanning else { return }
        scanning = true
        scriptQueue.async {
            let chrome = scanBrowser(.chrome), safari = scanBrowser(.safari)
            let all = chrome.tracks + safari.tracks + [scanMusic()].compactMap { $0 }
            let vol = Int(runScript("output volume of (get volume settings)").0 ?? "")
            let error = chrome.error ?? safari.error
            DispatchQueue.main.async { self.apply(all, vol, error) }
        }
    }

    private func apply(_ all: [Track], _ vol: Int?, _ error: String?) {
        scanning = false
        sources = all
        if all.count < 2 { showSources = false }
        // 재생 중인 것 > 방금까지 보던 것 > 아무거나
        let pick = all.first { $0.playing } ?? all.first { $0.key == track?.key } ?? all.first
        let switched = pick?.key != track?.key
        polledAt = Date()
        track = pick
        loadArtwork(pick)
        hint = pick == nil ? error.map(Deck.explain) : nil

        let now = Date()
        if let vol, !touching.master, now > holdUntil.master { master = Double(vol) }
        if let pick, switched || (!touching.source && now > holdUntil.source) { sourceVolume = Double(pick.volume) }
    }

    /// 곡이 바뀔 때만 커버를 새로 가져온다. 유튜브는 썸네일 주소, 애플뮤직은 AppleScript로 원본 이미지.
    private func loadArtwork(_ t: Track?) {
        let id = t?.artID ?? ""
        guard id != artID else { return }
        artID = id
        artwork = nil
        guard let t, !id.isEmpty else { return }
        let done = { (data: Data?) in
            let img = data.flatMap(NSImage.init(data:))   // 스트리밍 곡처럼 커버가 없으면 nil → 음표 아이콘
            DispatchQueue.main.async { if self.artID == id { self.artwork = img } }
        }
        if t.player == .music {
            scriptQueue.async {
                var err: NSDictionary?
                done(NSAppleScript(source: "tell application \"Music\" to return data of artwork 1 of current track")?
                    .executeAndReturnError(&err).data)
            }
        } else if let url = URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") {
            URLSession.shared.dataTask(with: url) { data, _, _ in done(data) }.resume()
        }
    }

    private static func explain(_ error: String) -> String {
        if error.contains("JavaScript") || error.contains("자바스크립트") {
            return "브라우저에서 'Apple Events의 JavaScript 허용'을 켜주세요"
        }
        if error.contains("-1743") || error.lowercased().contains("not authorized") {
            return "시스템 설정 › 개인정보 보호 › 자동화에서 MusicDeck을 허용해주세요"
        }
        return error
    }

    // MARK: 스태시 — PiP처럼 화면 끝으로 밀면 숨고, 손잡이를 누르면 나온다

    enum Side { case left, right, top }
    @Published var stashed: Side?
    @Published var lastSide = Side.right          // 손잡이를 누르면 이쪽으로 들어간다
    private static let peek: CGFloat = 22        // 숨었을 때 화면에 남는 폭
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var peeking = false                  // 손잡이로 꺼낸 뒤 아직 옮기지 않은 상태

    /// 창 끌기. 시스템 창 끌기는 창을 화면 안에 가두기 때문에 화면 밖으로 밀 수 있게 직접 옮긴다.
    func dragWindow() {
        guard let win = window, stashed == nil else { return }
        peeking = false         // 직접 옮기기 시작하면 더 이상 '잠깐 꺼낸' 상태가 아니다
        let m = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (m, win.frame.origin) }
        let d = dragStart!
        win.setFrameOrigin(NSPoint(x: d.origin.x + m.x - d.mouse.x, y: d.origin.y + m.y - d.mouse.y))
    }

    func endDrag() {
        dragStart = nil
        let m = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) { stashIfPastEdge(of: screen) }
    }

    /// 창이 화면 밖으로 30pt 넘게 나갔고, 그 바깥에 다른 모니터가 없으면 숨긴다
    private func stashIfPastEdge(of screen: NSScreen) {
        guard let f = window?.frame else { return }
        let s = screen.frame, top = screen.visibleFrame.maxY      // 위쪽은 메뉴 막대 아래가 기준
        let noScreen = { (p: NSPoint) in !NSScreen.screens.contains { NSMouseInRect(p, $0.frame, false) } }
        if f.maxX - s.maxX > 30, noScreen(NSPoint(x: s.maxX + 1, y: f.midY)) { stash(.right, on: screen) }
        else if s.minX - f.minX > 30, noScreen(NSPoint(x: s.minX - 1, y: f.midY)) { stash(.left, on: screen) }
        else if f.maxY - top > 30, noScreen(NSPoint(x: f.midX, y: s.maxY + 1)) { stash(.top, on: screen) }
    }

    /// 숨었을 때(hidden)와 꺼냈을 때의 창 위치
    private func frame(for side: Side, hidden: Bool, on screen: NSScreen) -> NSRect? {
        guard var f = window?.frame else { return nil }
        let s = screen.frame, top = screen.visibleFrame.maxY
        switch side {
        case .right: f.origin.x = hidden ? s.maxX - Deck.peek : s.maxX - f.width - 12
        case .left: f.origin.x = hidden ? s.minX - f.width + Deck.peek : s.minX + 12
        case .top: f.origin.y = hidden ? top - Deck.peek : top - f.height - 12
        }
        return f
    }

    /// 빈 곳 클릭(p는 창 안 좌표, 왼쪽 위 원점).
    /// 테두리 여백을 누르면 미는 방향으로 들어간다: 왼쪽 끝→오른쪽, 오른쪽 끝→왼쪽, 아래 끝→위.
    /// 그 밖의 빈 곳은 손잡이로 잠깐 꺼낸 상태일 때만 원래 자리로 돌아간다.
    func tapped(at p: CGPoint) {
        guard let size = window?.frame.size, let screen = window?.screen ?? NSScreen.main else { return }
        let band: CGFloat = 18
        let side: Side? = p.x < band ? .right
            : p.x > size.width - band ? .left
            : p.y > size.height - band ? .top
            : peeking ? lastSide : nil
        guard let side else { return }
        Click.press()
        stash(side, on: screen)
    }

    private func stash(_ side: Side, on screen: NSScreen) {
        guard let f = frame(for: side, hidden: true, on: screen) else { return }
        onTop = true            // 숨긴 손잡이가 다른 창에 가려지면 꺼낼 수 없으므로
        stashed = side
        lastSide = side
        peeking = false
        slide(to: f)
    }

    /// 손잡이: 숨어 있으면 꺼내고, 나와 있으면 마지막으로 숨었던 쪽으로 다시 넣는다
    func toggleStash() {
        Click.press()
        guard let screen = window?.screen ?? NSScreen.main else { return }
        guard let side = stashed else { return stash(lastSide, on: screen) }
        stashed = nil
        peeking = true
        if let f = frame(for: side, hidden: false, on: screen) { slide(to: f) }
    }

    private func slide(to f: NSRect) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().setFrame(f, display: true)
        })
    }

    func setMaster(_ v: Int) { holdUntil.master = Date() + 1.5; masterWriter.set(v) }
    func setSource(_ v: Int) { holdUntil.source = Date() + 1.5; if track != nil { sourceWriter.set(v) } }

    func togglePlay() { command(music: "playpause", js: jsToggle) }
    func next() { command(music: "next track", js: jsNext) }
    func previous() { command(music: "back track", js: jsPrev) }   // 앞부분이면 이전 곡, 아니면 처음부터

    func focus() {
        guard let t = track else { return }
        scriptQueue.async {
            switch t.player {
            case .music: _ = runScript("tell application \"Music\" to activate")
            case .chrome: _ = runScript("""
                tell application "Google Chrome"
                  set active tab index of window \(t.window) to \(t.tab)
                  set index of window \(t.window) to 1
                  activate
                end tell
                """)
            case .safari: _ = runScript("""
                tell application "Safari"
                  set current tab of window \(t.window) to tab \(t.tab) of window \(t.window)
                  set index of window \(t.window) to 1
                  activate
                end tell
                """)
            }
        }
    }

    private func command(music: String, js: String) {
        guard let t = track else { return }
        scriptQueue.async {
            send(t, music: music, js: js)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.poll() }
        }
    }

    // MARK: 소스 고르기 — 여러 곳이 열려 있을 때 목록에서 골라 재생한다

    @Published var sources: [Track] = []
    @Published var showSources = false

    /// 고른 곳을 재생하고, 다른 곳에서 재생 중이던 건 멈춘다(두 곳에서 동시에 소리가 나지 않게)
    func choose(_ t: Track) {
        showSources = false
        let others = sources.filter { $0.playing && $0.key != t.key }
        track = t
        loadArtwork(t)
        scriptQueue.async {
            for o in others { send(o, music: "pause", js: jsPause) }
            if !t.playing { send(t, music: "play", js: jsPlay) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.poll() }
        }
    }

    /// 내용 높이가 바뀌면(소스 목록 펼치기) 위쪽을 고정한 채 창 높이를 맞춘다
    func fit(_ size: CGSize) {
        guard let win = window, stashed == nil, abs(win.frame.height - size.height) > 0.5 else { return }
        var f = win.frame
        f.origin.y += f.height - size.height
        f.size = size
        win.setFrame(f, display: true)
    }
}
