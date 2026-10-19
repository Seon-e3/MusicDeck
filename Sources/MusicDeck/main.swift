import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // Dock 아이콘 없이 실행

/// macOS는 창이 메뉴 막대 위로 올라가지 못하게 위치를 보정한다. 위쪽 숨기기를 위해 보정을 끈다.
final class DeckPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

let deck = Deck()
let panel = DeckPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = Deck.desktopLevel       // 바탕화면 아이콘 바로 위, 다른 창들 아래
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
let host = NSHostingView(rootView: DeckView(deck: deck))
host.sizingOptions = []                // 창 크기는 Deck.fit이 위쪽을 고정한 채 맞춘다
panel.contentView = host
panel.setContentSize(host.fittingSize)
if !panel.setFrameUsingName("MusicDeck") { panel.center() }
panel.setFrameAutosaveName("MusicDeck")
panel.orderFrontRegardless()

deck.window = panel
deck.start()
app.run()
