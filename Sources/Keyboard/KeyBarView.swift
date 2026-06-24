import UIKit

/// The on-screen modifier key bar shown above the keyboard (and in the shortcut bar when a
/// hardware keyboard is attached). Horizontally scrollable so every key fits on a narrow
/// iPhone. Drives an `AppTerminalView` via its key-intent API.
final class KeyBarView: UIInputView {

    private weak var terminal: AppTerminalView?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?
    private var gestureHandlers: [GestureHandler] = []

    private let stack = UIStackView()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selection = UISelectionFeedbackGenerator()

    private let barHeight: CGFloat = 50

    init(terminal: AppTerminalView, width: CGFloat) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 50), inputViewStyle: .keyboard)
        autoresizingMask = .flexibleWidth
        allowsSelfSizing = true
        impact.prepare()
        buildBar()
        terminal.onModifiersChanged = { [weak self] in self?.refreshModifiers() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: barHeight) }

    private func buildBar() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.keyboardDismissMode = .none
        addSubview(scroll)

        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -6),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -12),
        ])

        // Modifiers (sticky: tap = one-shot, double-tap = lock)
        ctrlButton = addModifierKey("ctrl") { [weak self] lock in self?.terminal?.cycleControl(lock: lock) }
        altButton  = addModifierKey("alt")  { [weak self] lock in self?.terminal?.cycleMeta(lock: lock) }

        // Immediate keys (navigation)
        addKey("esc")  { $0.keyEsc() }
        addKey("tab")  { $0.keyTab() }
        addKey("⇧tab") { $0.keyBackTab() }
        addKey("←")   { $0.keyArrow(.left) }
        addKey("↓")   { $0.keyArrow(.down) }
        addKey("↑")   { $0.keyArrow(.up) }
        addKey("→")   { $0.keyArrow(.right) }
        addKey("⏎")   { $0.keyNewline() }       // Ctrl-J multiline (coding agents)
        addKey("⌫→")  { $0.keyForwardDelete() } // forward delete
        addKey("pg↑")  { $0.keyPageUp() }
        addKey("pg↓")  { $0.keyPageDown() }
        addKey("home") { $0.keyHome() }
        addKey("end")  { $0.keyEnd() }

        // Common control chords + tmux
        addKey("^C") { $0.keyInterrupt() }
        addKey("^D") { $0.keyControl("d") }      // EOF
        addKey("^L") { $0.keyControl("l") }      // clear
        addKey("^R") { $0.keyControl("r") }      // reverse search
        addKey("^Z") { $0.keyControl("z") }      // suspend
        addTmuxKey()

        // Editing / clipboard
        addKey("paste") { $0.keyPaste() }

        // Shell/agent punctuation
        for lit: Character in ["{", "}", "[", "]", "$", "*", "<", ">", "#", "|", "~", "/", "-"] {
            addKey(String(lit)) { $0.send([UInt8(lit.asciiValue!)]) }
        }

        // Font size
        addKey("A-") { $0.adjustFont(by: -1) }
        addKey("A+") { $0.adjustFont(by: 1) }

        refreshModifiers()
    }

    /// tmux button whose tap opens a chord menu (each sends prefix Ctrl-B + a key).
    private func addTmuxKey() {
        let b = styledButton("tmux")
        let chords: [(String, Character)] = [
            ("Copy-mode (scroll)", "["), ("Detach", "d"), ("New window", "c"),
            ("Next window", "n"), ("Prev window", "p"), ("Zoom pane", "z"),
            ("Split ⬍", "\""), ("Split ⬌", "%"),
        ]
        b.menu = UIMenu(title: "tmux  (prefix ^B)", children: chords.map { item in
            UIAction(title: item.0) { [weak self] _ in
                self?.impact.impactOccurred()
                self?.terminal?.tmuxChord(item.1)
            }
        })
        b.showsMenuAsPrimaryAction = true
        stack.addArrangedSubview(b)
    }

    // MARK: - Key builders

    private func styledButton(_ title: String) -> UIButton {
        var cfg = UIButton.Configuration.gray()
        cfg.title = title
        cfg.baseForegroundColor = .label
        cfg.cornerStyle = .medium
        cfg.titleLineBreakMode = .byClipping
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        cfg.titleTextAttributesTransformer = .init { incoming in
            var out = incoming
            out.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
            return out
        }
        let b = UIButton(configuration: cfg)
        b.titleLabel?.numberOfLines = 1
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        return b
    }

    private func addKey(_ title: String, action: @escaping (AppTerminalView) -> Void) {
        let b = styledButton(title)
        b.addAction(UIAction { [weak self] _ in
            guard let self, let t = self.terminal else { return }
            self.impact.impactOccurred()
            action(t)
        }, for: .touchUpInside)
        stack.addArrangedSubview(b)
    }

    /// A sticky modifier key wired with single-tap (one-shot) and double-tap (lock) recognizers.
    private func addModifierKey(_ title: String, toggle: @escaping (_ lock: Bool) -> Void) -> UIButton {
        let b = styledButton(title)

        let singleHandler = GestureHandler { [weak self] in self?.selection.selectionChanged(); toggle(false) }
        let doubleHandler = GestureHandler { [weak self] in self?.selection.selectionChanged(); toggle(true) }
        gestureHandlers.append(contentsOf: [singleHandler, doubleHandler])

        let double = UITapGestureRecognizer(target: doubleHandler, action: #selector(GestureHandler.fire))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: singleHandler, action: #selector(GestureHandler.fire))
        single.numberOfTapsRequired = 1
        single.require(toFail: double)

        b.addGestureRecognizer(single)
        b.addGestureRecognizer(double)
        stack.addArrangedSubview(b)
        return b
    }

    private func refreshModifiers() {
        applyModifierVisual(ctrlButton, state: terminal?.controlSticky ?? .off)
        applyModifierVisual(altButton, state: terminal?.metaSticky ?? .off)
    }

    private func applyModifierVisual(_ button: UIButton?, state: AppTerminalView.Sticky) {
        guard let button, var cfg = button.configuration else { return }
        switch state {
        case .off:
            cfg.baseBackgroundColor = nil
            cfg.background.strokeWidth = 0
        case .oneShot:
            cfg.baseBackgroundColor = .tintColor
            cfg.background.strokeWidth = 0
        case .locked:
            cfg.baseBackgroundColor = .tintColor
            cfg.background.strokeColor = .label
            cfg.background.strokeWidth = 2
        }
        button.configuration = cfg
    }
}

/// Tiny target object that turns a gesture-recognizer callback into a closure.
final class GestureHandler: NSObject {
    private let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}
