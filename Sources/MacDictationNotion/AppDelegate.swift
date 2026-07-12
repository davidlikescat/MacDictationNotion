import AppKit
import Network
import MacDictationNotionCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum AppState: Equatable {
        case idle, recording, sending, notConfigured
    }

    private var statusItem: NSStatusItem!
    private let hotKey = HotKeyManager()
    private var pipeline: DictationPipeline?
    private let offlineQueue = OfflineQueue()
    private let netMonitor   = NWPathMonitor()
    private var isOnline     = true
    private var settingsWindow: SettingsWindowController?
    private let hud = RecordingHUDController()

    private var appState: AppState = .idle {
        didSet { DispatchQueue.main.async { self.refreshUI() } }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationMenu()
        setupStatusItem()
        Notifier.requestAuthorization()
        requestAccessibilityPermission()
        loadSettings()
        setupHotKey()
        startNetworkMonitor()

        SpeechRecognizer.requestAuthorization { granted in
            if !granted {
                Notifier.notify(title: "Permission required",
                                body: "Enable Microphone and Speech Recognition in System Settings > Privacy & Security.")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        netMonitor.cancel()
    }

    // MARK: - Accessibility permission

    private func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        if !trusted {
            Notifier.notify(
                title: "Accessibility permission required",
                body: "Go to System Settings > Privacy & Security > Accessibility and enable MacDictationNotion."
            )
        }
    }

    // MARK: - Application menu (enables ⌘V/⌘C/⌘X in text fields)

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit MacDictationNotion", action: #selector(quit), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut",       action: #selector(NSText.cut(_:)),      keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy",      action: #selector(NSText.copy(_:)),     keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste",     action: #selector(NSText.paste(_:)),    keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Settings

    private func loadSettings() {
        do {
            let loaded = try Settings.load()
            guard loaded.isValid else {
                pipeline = nil
                appState = .notConfigured
                Notifier.notify(title: "Setup required",
                                body: "Enter your notionToken and databaseId in config.json.")
                return
            }

            let recognizer = SpeechRecognizer(localeIdentifier: loaded.locale)
            let refiner    = LLMRefiner(settings: loaded)
            let client     = NotionClient(settings: loaded)
            let p          = DictationPipeline(recognizer: recognizer, refiner: refiner, client: client)

            p.onStateChange = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .idle:      self.appState = .idle
                case .recording: self.appState = .recording
                case .refining, .sending: self.appState = .sending
                }
            }
            p.onPartialTranscript = { [weak self] text in
                self?.statusItem.button?.toolTip = "Recording: …\(text.suffix(40))"
                self?.hud.updateTranscript(text)
            }
            p.onAudioLevel = { [weak self] level in
                self?.hud.setAudioLevel(level)
            }
            p.onSuccess = { [weak self] text in
                guard let self = self else { return }
                self.hud.hide()
                self.playSound("Glass")
                Notifier.notify(title: "Sent to Notion", body: String(text.prefix(60)))
                self.refreshUI()
            }
            p.onFailure = { [weak self] error in
                guard let self = self else { return }
                self.hud.hide()
                switch error {
                case .emptyTranscript:
                    Notifier.notify(title: "Nothing recognized", body: "Please try again.")
                case .recognizerError(let msg):
                    Notifier.notify(title: "Dictation failed to start", body: msg)
                case .notionError(let e):
                    if e.isRetryable {
                        Notifier.notify(title: "Offline — could not queue",
                                        body: "Check your network connection.")
                    } else {
                        Notifier.notify(title: "Send failed", body: e.userMessage)
                    }
                }
                self.refreshUI()
            }

            pipeline = p
            hotKey.register(keyCode: UInt32(loaded.hotkeyKeyCode),
                            modifiers: UInt32(loaded.hotkeyModifiers))
            appState = .idle
            flushQueue(settings: loaded)
        } catch {
            pipeline = nil
            appState = .notConfigured
            Settings.ensureExampleExists()
            Notifier.notify(title: "No config found",
                            body: "Open Preferences from the menu bar icon to set up MacDictationNotion.")
        }
    }

    // MARK: - Status item / menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshUI()
    }

    private func refreshUI() {
        guard let button = statusItem.button else { return }
        let (symbol, tooltip): (String, String)
        switch appState {
        case .idle:
            symbol = "mic"; tooltip = "Ready"
        case .recording:
            symbol = "mic.fill"; tooltip = "Recording — press hotkey again to stop"
        case .sending:
            symbol = "arrow.up.circle"; tooltip = "Sending..."
        case .notConfigured:
            symbol = "exclamationmark.triangle"; tooltip = "Setup required"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        button.image   = image
        button.toolTip = tooltip
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggleTitle = (appState == .recording) ? "Stop Dictation" : "Start Dictation"
        let toggleItem  = NSMenuItem(title: toggleTitle, action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.target    = self
        toggleItem.isEnabled = (appState == .idle || appState == .recording)
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let pending = offlineQueue.count
        let pendingItem = NSMenuItem(title: "Pending retry: \(pending)", action: nil, keyEquivalent: "")
        pendingItem.isEnabled = false
        menu.addItem(pendingItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Preferences...", action: #selector(openSettings), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        let reloadItem = NSMenuItem(title: "Reload Settings", action: #selector(reloadConfig), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let howToItem = NSMenuItem(title: "How to Use...", action: #selector(openHowToUse), keyEquivalent: "")
        howToItem.target = self
        menu.addItem(howToItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu actions

    @objc private func toggleFromMenu() { toggleDictation() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let wc = SettingsWindowController()
            wc.onSave = { [weak self] in self?.loadSettings() }
            settingsWindow = wc
        }
        settingsWindow?.showWindow(nil)
    }

    @objc private func reloadConfig() { loadSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openHowToUse() {
        if let url = URL(string: "https://aicoder-lab.blogspot.com/2026/07/macdictationnotion-voice-notes-notion.html") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Hot key

    private func setupHotKey() {
        hotKey.onTrigger = { [weak self] in
            DispatchQueue.main.async { self?.toggleDictation() }
        }
    }

    // MARK: - Dictation flow

    private func toggleDictation() {
        switch appState {
        case .notConfigured:
            Notifier.notify(title: "Setup required", body: "Open Preferences to configure MacDictationNotion.")
        case .sending:
            break
        case .recording:
            hud.updateStatus("Sending...")
            playSound("Pop")
            pipeline?.stop()
        case .idle:
            guard let pipeline = pipeline else { return }
            hud.onCancel = { [weak self] in
                self?.pipeline?.cancel()
                self?.hud.hide()
                self?.playSound("Pop")
            }
            do {
                try pipeline.start()
                playSound("Tink")
                hud.show(hotkey: hotkeyLabel())
            } catch {
                let msg = (error as? RecognizerError)?.errorDescription ?? error.localizedDescription
                Notifier.notify(title: "Dictation failed to start", body: msg)
            }
        }
    }

    // MARK: - Offline queue

    private func flushQueue(settings: Settings) {
        let items = offlineQueue.load()
        guard !items.isEmpty else { return }
        let client = NotionClient(settings: settings)

        func sendNext(_ remaining: ArraySlice<OfflineQueue.Item>) {
            guard let first = remaining.first else {
                DispatchQueue.main.async { self.refreshUI() }
                return
            }
            client.send(text: first.text) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.offlineQueue.remove(first)
                    sendNext(remaining.dropFirst())
                case .failure(let e):
                    if !e.isRetryable {
                        self.offlineQueue.remove(first)
                        sendNext(remaining.dropFirst())
                    }
                }
            }
        }
        sendNext(items[...])
    }

    // MARK: - Network monitoring

    private func startNetworkMonitor() {
        netMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let online = (path.status == .satisfied)
            DispatchQueue.main.async {
                let wasOffline = !self.isOnline
                self.isOnline  = online
                if online && wasOffline, let s = try? Settings.load(), s.isValid {
                    self.flushQueue(settings: s)
                }
            }
        }
        netMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Hotkey display

    private func hotkeyLabel() -> String {
        guard let s = try? Settings.load() else { return "단축키" }
        let mod = UInt32(s.hotkeyModifiers)
        var label = ""
        if mod & 4096 != 0 { label += "⌃" }
        if mod & 2048 != 0 { label += "⌥" }
        if mod & 512  != 0 { label += "⇧" }
        if mod & 256  != 0 { label += "⌘" }
        let map: [UInt32: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",
            31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",49:"Space",
        ]
        label += map[UInt32(s.hotkeyKeyCode)] ?? "?"
        return label
    }

    // MARK: - Sound

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
