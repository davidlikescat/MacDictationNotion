import AppKit
import MacDictationNotionCore

// MARK: - Key capture field

private final class HotkeyField: NSTextField {
    private(set) var capturedKeyCode: UInt32
    private(set) var capturedModifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        capturedKeyCode   = keyCode
        capturedModifiers = modifiers
        super.init(frame: .zero)
        // Non-editable: prevents field editor from taking over as first responder.
        isEditable   = false
        isSelectable = false
        isBezeled    = true
        bezelStyle   = .roundedBezel
        alignment    = .center
        stringValue  = Self.display(keyCode: keyCode, modifiers: modifiers)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setHotkey(keyCode: UInt32, modifiers: UInt32) {
        capturedKeyCode   = keyCode
        capturedModifiers = modifiers
        stringValue = Self.display(keyCode: keyCode, modifiers: modifiers)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    // Intercepts ⌘-key combos BEFORE the menu bar handles them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        return capture(event)
    }

    override func keyDown(with event: NSEvent) {
        if !capture(event) { super.keyDown(with: event) }
    }

    @discardableResult
    private func capture(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 63]
        guard event.keyCode != 53,                    // Escape → blur, don't capture
              !modifierKeys.contains(event.keyCode),  // ignore bare modifier keys
              !mods.isEmpty else { return false }

        capturedKeyCode   = UInt32(event.keyCode)
        capturedModifiers = Self.carbonMask(from: mods)
        stringValue = Self.display(keyCode: capturedKeyCode, modifiers: capturedModifiers)
        return true
    }

    // MARK: - Helpers

    private static func carbonMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= 4096 }
        if flags.contains(.option)  { m |= 2048 }
        if flags.contains(.shift)   { m |= 512  }
        if flags.contains(.command) { m |= 256  }
        return m
    }

    static func display(keyCode: UInt32, modifiers: UInt32) -> String {
        var s = ""
        if modifiers & 4096 != 0 { s += "⌃" }
        if modifiers & 2048 != 0 { s += "⌥" }
        if modifiers & 512  != 0 { s += "⇧" }
        if modifiers & 256  != 0 { s += "⌘" }
        s += keyLabel(keyCode)
        return s
    }

    private static func keyLabel(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
             0:"A",  1:"S",  2:"D",  3:"F",  4:"H",  5:"G",  6:"Z",  7:"X",
             8:"C",  9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R",
            16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6",
            23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0",
            30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P",
            37:"L", 38:"J", 39:"'", 40:"K", 41:";", 42:"\\",
            45:"N", 46:"M", 47:",", 48:"Tab", 49:"Space", 50:"`",
            51:"Delete", 65:".", 67:"*", 69:"+", 75:"/", 78:"-", 81:"=",
            82:"0", 83:"1", 84:"2", 85:"3", 86:"4", 87:"5",
            88:"6", 89:"7", 91:"8", 92:"9",
             96:"F5",  97:"F6",  98:"F7",  99:"F3", 100:"F8", 101:"F9",
            103:"F11",109:"F10",111:"F12",118:"F4", 120:"F2",122:"F1",
            123:"←", 124:"→", 125:"↓", 126:"↑",
        ]
        return map[code] ?? "(\(code))"
    }
}

// MARK: - Settings window

final class SettingsWindowController: NSWindowController {

    private var tokenField: NSTextField!
    private var dbIdField: NSTextField!
    private var titlePropField: NSTextField!
    private var localeField: NSTextField!
    private var prefixField: NSTextField!
    private var hotkeyField: HotkeyField!
    private var llmCheckbox: NSButton!
    private var ollamaModelField: NSTextField!

    var onSave: (() -> Void)?

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "MacDictationNotion Preferences"
        win.isReleasedWhenClosed = false
        super.init(window: win)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        loadCurrentValues()
        window?.center()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI

    private func makeLabel(_ text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.alignment = .right
        return lbl
    }

    private func makeField(placeholder: String) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = placeholder
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }

        tokenField     = makeField(placeholder: "secret_... or ntn_...")
        dbIdField      = makeField(placeholder: "32-char ID (no hyphens)")
        titlePropField = makeField(placeholder: "Name")
        localeField    = makeField(placeholder: "en-US")
        prefixField    = makeField(placeholder: "Voice memo:")
        hotkeyField    = HotkeyField(keyCode: 2, modifiers: 768)
        hotkeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        llmCheckbox = NSButton(checkboxWithTitle: "Refine text with Ollama (llmRefine)", target: nil, action: nil)
        ollamaModelField = makeField(placeholder: "qwen2.5:7b")

        let grid = NSGridView(views: [
            [makeLabel("Notion Token *"), tokenField!],
            [makeLabel("Database ID *"),  dbIdField!],
            [makeLabel("Title property"), titlePropField!],
            [makeLabel("Language"),       localeField!],
            [makeLabel("Prefix"),         prefixField!],
            [makeLabel("Hotkey"),         hotkeyField!],
            [makeLabel("LLM Refine"),     llmCheckbox!],
            [makeLabel("Ollama model"),   ollamaModelField!],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)

        let note = NSTextField(labelWithString: "* Required. Click the Hotkey field and press your desired key combo. Changes apply on save.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(note)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancelBtn.keyEquivalent = "\u{1b}"
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveBtn.keyEquivalent = "\r"

        let btnStack = NSStackView(views: [cancelBtn, saveBtn])
        btnStack.spacing = 8
        btnStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(btnStack)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
            note.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),

            btnStack.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12),
            btnStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            btnStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Load / Save

    private func loadCurrentValues() {
        guard let settings = try? Settings.load() else { return }
        tokenField.stringValue     = settings.notionToken
        dbIdField.stringValue      = settings.databaseId
        titlePropField.stringValue = settings.titleProperty
        localeField.stringValue    = settings.locale
        prefixField.stringValue    = settings.notePrefix
        hotkeyField.setHotkey(keyCode: UInt32(settings.hotkeyKeyCode),
                              modifiers: UInt32(settings.hotkeyModifiers))
        llmCheckbox.state = settings.llmRefine ? .on : .off
        ollamaModelField.stringValue = settings.ollamaModel
    }

    @objc private func saveAction() {
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespaces)
        let dbId  = dbIdField.stringValue.trimmingCharacters(in: .whitespaces)

        guard !token.isEmpty, !dbId.isEmpty else {
            showAlert("Missing required fields", "Please enter a Notion Token and Database ID.")
            return
        }

        let config: [String: Any] = [
            "notionToken":    token,
            "databaseId":     dbId,
            "titleProperty":  titlePropField.stringValue.isEmpty ? "Name"  : titlePropField.stringValue,
            "locale":         localeField.stringValue.isEmpty    ? "ko-KR" : localeField.stringValue,
            "notePrefix":     prefixField.stringValue,
            "notionVersion":  "2022-06-28",
            "hotkeyKeyCode":  Int(hotkeyField.capturedKeyCode),
            "hotkeyModifiers": Int(hotkeyField.capturedModifiers),
            "llmRefine":      llmCheckbox.state == .on,
            "ollamaModel":    ollamaModelField.stringValue.isEmpty ? "qwen2.5:7b" : ollamaModelField.stringValue,
        ]

        do {
            Settings.ensureExampleExists()
            let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
            try data.write(to: Settings.configURL, options: .atomic)
            close()
            onSave?()
        } catch {
            showAlert("Save failed", error.localizedDescription)
        }
    }

    @objc private func cancelAction() { close() }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        if let win = window { alert.beginSheetModal(for: win) { _ in } }
    }
}
