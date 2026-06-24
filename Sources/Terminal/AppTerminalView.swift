import UIKit
import SwiftTerm

/// SwiftTerm `TerminalView` subclass that:
///  - becomes first responder automatically so the keyboard + key bar appear,
///  - exposes high-level "key intents" the on-screen `KeyBarView` calls,
///  - models Ctrl/Alt as sticky modifiers (one-shot or locked) by driving SwiftTerm's
///    own `controlModifier`/`metaModifier` (so soft-keyboard input is transformed by
///    SwiftTerm's tested `insertText` path — single source of truth).
final class AppTerminalView: TerminalView {

    enum Sticky: Equatable { case off, oneShot, locked }
    enum Arrow { case up, down, left, right }

    /// Called whenever a sticky modifier changes, so the key bar can refresh visuals.
    var onModifiersChanged: (() -> Void)?

    var controlSticky: Sticky = .off {
        didSet { controlModifier = (controlSticky != .off); onModifiersChanged?() }
    }
    var metaSticky: Sticky = .off {
        didSet { metaModifier = (metaSticky != .off); onModifiersChanged?() }
    }

    // SwiftTerm's reset notification names are internal to the module; reference them by
    // their stable raw strings.
    private static let ctrlReset = Notification.Name("SwiftTerm.TerminalView.controlModifierReset")
    private static let metaReset = Notification.Name("SwiftTerm.TerminalView.metaModifierReset")

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        observeModifierResets()
        // SwiftTerm's CoreText draw erases the dirty rect with a TRANSPARENT color: setupOptions()
        // moves the opaque background onto `layer.backgroundColor` and sets
        // `nativeBackgroundColor = .clear`, and `draw(_:)` does `nativeBackgroundColor.set();
        // fill(dirtyRect)` — a no-op erase. On device the reused layer backing store is never
        // cleared, so glyphs composite over stale ones (ghosting on type, overlap on Return,
        // smear on scroll). Invisible on the Simulator (fresh backing per captured frame).
        // Fix: mark the view opaque and restore an OPAQUE erase color so each draw clears.
        // (We can't override the `public` (not `open`) draw(_:), so we drive nativeBackgroundColor.)
        isOpaque = true
        clearsContextBeforeDrawing = true
        restoreOpaqueBackground()
        applyFontSize()
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
    }

    // MARK: - Font size

    private var pinchBaseSize: CGFloat = 14

    func applyFontSize() {
        font = UIFont.monospacedSystemFont(ofSize: SettingsStore.fontSize, weight: .regular)
    }

    /// Bump the persisted font size and apply it (the resize is forwarded to the PTY by the delegate).
    func adjustFont(by delta: CGFloat) {
        SettingsStore.fontSize += delta
        applyFontSize()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchBaseSize = SettingsStore.fontSize
        case .changed:
            let target = (pinchBaseSize * g.scale).rounded()   // step by whole points to avoid reflow churn
            if abs(target - SettingsStore.fontSize) >= 1 {
                SettingsStore.fontSize = target
                applyFontSize()
            }
        default:
            break
        }
    }

    /// Undo SwiftTerm's `nativeBackgroundColor = .clear` so draw()'s background fill actually
    /// erases. Idempotent; re-asserted from layoutSubviews in case SwiftTerm resets it.
    private func restoreOpaqueBackground() {
        guard nativeBackgroundColor.cgColor.alpha < 1 else { return }
        let bg = layer.backgroundColor.map { UIColor(cgColor: $0) } ?? .black
        nativeBackgroundColor = bg.withAlphaComponent(1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        restoreOpaqueBackground()
    }

    private func observeModifierResets() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(controlWasReset), name: Self.ctrlReset, object: self)
        nc.addObserver(self, selector: #selector(metaWasReset), name: Self.metaReset, object: self)
    }

    // SwiftTerm cleared the flag after applying it to a soft-keyboard key.
    @objc private func controlWasReset() {
        switch controlSticky {
        case .oneShot: controlSticky = .off
        case .locked: controlModifier = true           // re-arm for the next key
        case .off: break
        }
        onModifiersChanged?()
    }

    @objc private func metaWasReset() {
        switch metaSticky {
        case .oneShot: metaSticky = .off
        case .locked: metaModifier = true
        case .off: break
        }
        onModifiersChanged?()
    }

    // MARK: - First responder

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !isFirstResponder {
            DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() }
        }
    }

    /// Force a redraw of the visible area when the scroll offset *actually* changes.
    ///
    /// SwiftTerm's CoreText path does NOT redraw on scroll (its own `contentOffset` observer only
    /// requests display for the Metal path), so it relies on UIScrollView's cached tiles, which go
    /// stale and smear. Redrawing on offset change fixes it (keeping CoreText's correct colors).
    /// We skip when the offset is unchanged — UIScrollView frequently re-sets an identical offset,
    /// and that would force a redundant full-bounds redraw on the streaming hot path.
    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            let changed = newValue != super.contentOffset
            super.contentOffset = newValue
            if changed { setNeedsDisplay(bounds) }
        }
    }

    // MARK: - Sticky modifier toggles (from the key bar)

    func cycleControl(lock: Bool) {
        if lock {
            controlSticky = (controlSticky == .locked) ? .off : .locked
        } else {
            controlSticky = (controlSticky == .off) ? .oneShot : .off
        }
    }

    func cycleMeta(lock: Bool) {
        if lock {
            metaSticky = (metaSticky == .locked) ? .off : .locked
        } else {
            metaSticky = (metaSticky == .off) ? .oneShot : .off
        }
    }

    /// Consume a one-shot Ctrl after applying it to an immediate (non-soft-keyboard) key.
    private func consumeControlIfOneShot() {
        if controlSticky == .oneShot { controlSticky = .off }
    }

    // MARK: - Immediate key intents

    func keyEsc()         { send(EscapeSequences.cmdEsc) }            // 0x1b
    func keyTab()         { send(EscapeSequences.cmdTab) }            // 0x09
    func keyBackTab()     { send(EscapeSequences.cmdBackTab) }        // ESC [ Z
    func keyNewline()     { send([0x0a]) }                            // Ctrl-J — coding agents multiline
    func keyTmuxPrefix()  { send([0x02]) }                            // Ctrl-B
    func keyInterrupt()   { send([0x03]) }                            // Ctrl-C
    func keyForwardDelete() { send(EscapeSequences.cmdDelKey) }       // ESC [ 3 ~
    func keyPageUp()      { send(EscapeSequences.cmdPageUp) }         // ESC [ 5 ~
    func keyPageDown()    { send(EscapeSequences.cmdPageDown) }       // ESC [ 6 ~
    func keyHome() { send(getTerminal().applicationCursor ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal) }
    func keyEnd()  { send(getTerminal().applicationCursor ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal) }

    /// Single-control byte for a letter (a→0x01 … z→0x1a), e.g. ^D, ^L, ^R, ^Z.
    func keyControl(_ letter: Character) {
        guard let a = letter.lowercased().first?.asciiValue, a >= 0x61, a <= 0x7a else { return }
        send([a - 0x60])
    }

    /// tmux chord: prefix (Ctrl-B) then the given key — copy-mode `[`, detach `d`, new-window `c`, etc.
    func tmuxChord(_ key: Character) {
        guard let a = key.asciiValue else { return }
        send([0x02, a])
    }

    /// Paste clipboard through SwiftTerm (bracketed-paste aware).
    func keyPaste() { paste(nil) }

    func scrollToBottom() { repositionVisibleFrame() }

    func toggleKeyboard() {
        if isFirstResponder { _ = resignFirstResponder() } else { _ = becomeFirstResponder() }
    }

    // MARK: - Scrollback search (SwiftTerm scrolls to + highlights the match)
    func searchNext(_ term: String) { _ = findNext(term) }
    func searchPrevious(_ term: String) { _ = findPrevious(term) }
    func searchClear() { clearSearch() }

    func keyArrow(_ a: Arrow) {
        // Ctrl+arrow → CSI 1;5 <dir> (word nav / tmux pane moves)
        if controlModifier {
            send(Self.ctrlArrow(a))
            consumeControlIfOneShot()
            return
        }
        let app = getTerminal().applicationCursor
        switch a {
        case .up:    send(app ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal)
        case .down:  send(app ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal)
        case .left:  send(app ? EscapeSequences.moveLeftApp : EscapeSequences.moveLeftNormal)
        case .right: send(app ? EscapeSequences.moveRightApp : EscapeSequences.moveRightNormal)
        }
    }

    private static func ctrlArrow(_ a: Arrow) -> [UInt8] {
        let final: UInt8
        switch a {
        case .up: final = 0x41; case .down: final = 0x42
        case .right: final = 0x43; case .left: final = 0x44
        }
        return [0x1b, 0x5b, 0x31, 0x3b, 0x35, final] // ESC [ 1 ; 5 <A/B/C/D>
    }
}
