import AppKit

// MARK: - Animated equalizer bars

private final class EqualizerView: NSView {
    private var bars: [NSView] = []
    private var heightConstraints: [NSLayoutConstraint] = []
    private var timer: Timer?
    private(set) var level: Float = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        buildBars()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildBars() {
        let barW: CGFloat = 4
        let gap:  CGFloat = 4
        for i in 0..<5 {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            bar.layer?.cornerRadius = 2
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
            let hc = bar.heightAnchor.constraint(equalToConstant: 3)
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: barW),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor),
                bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CGFloat(i) * (barW + gap)),
                hc,
            ])
            bars.append(bar)
            heightConstraints.append(hc)
        }
    }

    func startAnimation() {
        level = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.animateStep()
        }
    }

    func stopAnimation() {
        timer?.invalidate(); timer = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.allowsImplicitAnimation = true
            heightConstraints.forEach { $0.animator().constant = 3 }
        }
    }

    func setLevel(_ newLevel: Float) { level = newLevel }

    private func animateStep() {
        let base = CGFloat(max(0.08, level))
        let maxH = bounds.height > 0 ? bounds.height : 20
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            ctx.allowsImplicitAnimation = true
            for hc in heightConstraints {
                let v = CGFloat.random(in: 0.3...1.0)
                let target = max(3, min(maxH, maxH * base * v + CGFloat.random(in: 1...4)))
                hc.animator().constant = target
            }
        }
    }
}

// MARK: - Floating HUD panel

final class RecordingHUDController: NSObject {
    private var panel: NSPanel?
    private var equalizerView: EqualizerView!
    private var transcriptLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var escMonitor: Any?

    var onCancel: (() -> Void)?

    // MARK: - Public API

    func show(hotkey: String = "⌘⇧D") {
        if panel == nil { buildPanel() }
        statusLabel.stringValue = "\(hotkey) to send · ESC to cancel"
        transcriptLabel.stringValue = ""
        panel?.alphaValue = 0
        panel?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.panel?.animator().alphaValue = 1
        }
        equalizerView.startAnimation()
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.onCancel?() }  // 53 = ESC
        }
    }

    func hide() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        equalizerView.stopAnimation()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 0
        }, completionHandler: {
            self.panel?.orderOut(nil)
        })
    }

    @objc private func closeTapped() { onCancel?() }

    func updateTranscript(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.transcriptLabel.stringValue = text
        }
    }

    func updateStatus(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.stringValue = text
        }
    }

    func setAudioLevel(_ level: Float) {
        equalizerView.setLevel(level)
    }

    // MARK: - Panel construction

    private func buildPanel() {
        let w: CGFloat = 340, h: CGFloat = 112
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let origin = CGPoint(x: sf.midX - w / 2, y: sf.minY + 52)

        let p = NSPanel(
            contentRect: CGRect(origin: origin, size: CGSize(width: w, height: h)),
            styleMask:   [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing:     .buffered,
            defer:       false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = p.contentView!

        // Dark blurred background
        let ve = NSVisualEffectView(frame: content.bounds)
        ve.material = .hudWindow
        ve.blendingMode = .behindWindow
        ve.state = .active
        ve.wantsLayer = true
        ve.layer?.cornerRadius = 14
        ve.layer?.masksToBounds = true
        ve.autoresizingMask = [.width, .height]
        content.addSubview(ve)

        // Mic icon
        let mic = NSImageView()
        mic.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        mic.contentTintColor = .white
        mic.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        mic.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(mic)

        // Equalizer
        equalizerView = EqualizerView(frame: .zero)
        equalizerView.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(equalizerView)

        // Status (hotkey hint)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(statusLabel)

        // X (cancel) button
        let closeBtn = NSButton(title: "", target: self, action: #selector(closeTapped))
        let xImg = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cancel")
        closeBtn.image = xImg
        closeBtn.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        closeBtn.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        closeBtn.bezelStyle = .regularSquare
        closeBtn.isBordered = false
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(closeBtn)

        // Divider
        let div = NSView()
        div.wantsLayer = true
        div.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        div.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(div)

        // Live transcript
        transcriptLabel = NSTextField(wrappingLabelWithString: "")
        transcriptLabel.textColor = .white
        transcriptLabel.font = .systemFont(ofSize: 13, weight: .regular)
        transcriptLabel.maximumNumberOfLines = 3
        transcriptLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(transcriptLabel)

        NSLayoutConstraint.activate([
            mic.leadingAnchor.constraint(equalTo: ve.leadingAnchor, constant: 14),
            mic.topAnchor.constraint(equalTo: ve.topAnchor, constant: 14),
            mic.widthAnchor.constraint(equalToConstant: 18),
            mic.heightAnchor.constraint(equalToConstant: 18),

            equalizerView.leadingAnchor.constraint(equalTo: mic.trailingAnchor, constant: 8),
            equalizerView.centerYAnchor.constraint(equalTo: mic.centerYAnchor),
            equalizerView.widthAnchor.constraint(equalToConstant: 36),
            equalizerView.heightAnchor.constraint(equalToConstant: 18),

            statusLabel.leadingAnchor.constraint(equalTo: equalizerView.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: mic.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeBtn.leadingAnchor, constant: -6),

            closeBtn.trailingAnchor.constraint(equalTo: ve.trailingAnchor, constant: -12),
            closeBtn.centerYAnchor.constraint(equalTo: mic.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 18),
            closeBtn.heightAnchor.constraint(equalToConstant: 18),

            div.topAnchor.constraint(equalTo: mic.bottomAnchor, constant: 10),
            div.leadingAnchor.constraint(equalTo: ve.leadingAnchor, constant: 14),
            div.trailingAnchor.constraint(equalTo: ve.trailingAnchor, constant: -14),
            div.heightAnchor.constraint(equalToConstant: 1),

            transcriptLabel.topAnchor.constraint(equalTo: div.bottomAnchor, constant: 8),
            transcriptLabel.leadingAnchor.constraint(equalTo: ve.leadingAnchor, constant: 14),
            transcriptLabel.trailingAnchor.constraint(equalTo: ve.trailingAnchor, constant: -14),
            transcriptLabel.bottomAnchor.constraint(lessThanOrEqualTo: ve.bottomAnchor, constant: -10),
        ])

        panel = p
    }
}
