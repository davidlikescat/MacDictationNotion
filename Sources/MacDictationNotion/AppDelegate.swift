import AppKit
import Network

final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum State: Equatable {
        case idle          // 대기 중
        case recording     // 녹음 중
        case sending       // 노션 전송 중
        case notConfigured // 설정 필요
    }

    private var statusItem: NSStatusItem!
    private var settings: Settings?
    private let hotKey = HotKeyManager()
    private var recognizer: SpeechRecognizer?
    private var notion: NotionClient?
    private let offlineQueue = OfflineQueue()
    private let netMonitor = NWPathMonitor()
    private var isOnline = true

    private var state: State = .idle {
        didSet { DispatchQueue.main.async { self.refreshUI() } }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        Notifier.requestAuthorization()
        loadSettings()
        setupHotKey()
        startNetworkMonitor()

        // Prompt for mic + speech permission up front so the first dictation is smooth.
        SpeechRecognizer.requestAuthorization { granted in
            if !granted {
                Notifier.notify(title: "권한 필요",
                                body: "시스템 설정 › 개인정보 보호 및 보안에서 ‘마이크’와 ‘음성 인식’을 허용해 주세요.")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        netMonitor.cancel()
    }

    // MARK: - Settings

    private func loadSettings() {
        do {
            let loaded = try Settings.load()
            guard loaded.isValid else {
                settings = nil
                state = .notConfigured
                Notifier.notify(title: "설정 필요",
                                body: "config.json에 notionToken과 databaseId를 입력해 주세요.")
                return
            }
            settings = loaded
            recognizer = SpeechRecognizer(localeIdentifier: loaded.locale)
            notion = NotionClient(settings: loaded)
            state = .idle
            flushQueue() // Retry anything left over from a previous session.
        } catch {
            settings = nil
            state = .notConfigured
            Settings.ensureExampleExists()
            Notifier.notify(title: "설정 파일 없음",
                            body: "메뉴에서 ‘설정 파일 열기’를 눌러 config.json을 작성해 주세요.")
        }
    }

    // MARK: - Status item / menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshUI()
    }

    private func refreshUI() {
        guard let button = statusItem.button else { return }
        let symbol: String
        let tooltip: String
        switch state {
        case .idle:
            symbol = "mic"; tooltip = "대기 중 — ⌘⇧D로 받아쓰기 시작"
        case .recording:
            symbol = "mic.fill"; tooltip = "녹음 중 — ⌘⇧D로 종료 및 전송"
        case .sending:
            symbol = "arrow.up.circle"; tooltip = "노션으로 전송 중…"
        case .notConfigured:
            symbol = "exclamationmark.triangle"; tooltip = "설정 필요 — config.json을 작성하세요"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        image?.isTemplate = true
        button.image = image
        button.toolTip = tooltip
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggleTitle = (state == .recording) ? "받아쓰기 중지 (⌘⇧D)" : "받아쓰기 시작 (⌘⇧D)"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = (state == .idle || state == .recording)
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let pending = offlineQueue.count
        let pendingItem = NSMenuItem(title: "재전송 대기: \(pending)건", action: nil, keyEquivalent: "")
        pendingItem.isEnabled = false
        menu.addItem(pendingItem)

        if pending > 0 {
            let retryItem = NSMenuItem(title: "지금 재전송", action: #selector(retryNow), keyEquivalent: "")
            retryItem.target = self
            menu.addItem(retryItem)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "설정 파일 열기", action: #selector(openConfig), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let reloadItem = NSMenuItem(title: "설정 다시 불러오기", action: #selector(reloadConfig), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu actions

    @objc private func toggleFromMenu() { toggleDictation() }
    @objc private func retryNow() { flushQueue() }

    @objc private func openConfig() {
        let url = Settings.ensureExampleExists()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func reloadConfig() { loadSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Hot key

    private func setupHotKey() {
        hotKey.onTrigger = { [weak self] in
            DispatchQueue.main.async { self?.toggleDictation() }
        }
        hotKey.register()
    }

    // MARK: - Dictation flow

    private func toggleDictation() {
        switch state {
        case .notConfigured:
            Notifier.notify(title: "설정 필요", body: "config.json을 먼저 작성해 주세요.")
        case .sending:
            break // 전송 중에는 무시
        case .recording:
            finishDictation()
        case .idle:
            startDictation()
        }
    }

    private func startDictation() {
        guard let recognizer = recognizer else { return }
        recognizer.onPartial = { [weak self] text in
            self?.statusItem.button?.toolTip = "녹음 중: …\(text.suffix(40))"
        }
        do {
            try recognizer.startRecording()
            playSound("Tink")   // 시작을 알리는 '띵'
            state = .recording
        } catch {
            let message = (error as? RecognizerError)?.errorDescription ?? error.localizedDescription
            Notifier.notify(title: "받아쓰기 시작 실패", body: message)
            state = .idle
        }
    }

    private func finishDictation() {
        guard let recognizer = recognizer else { return }
        state = .sending
        playSound("Pop")
        recognizer.stopRecording { [weak self] text in
            guard let self = self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                Notifier.notify(title: "인식된 내용 없음", body: "다시 시도해 주세요.")
                self.state = .idle
                return
            }
            self.sendToNotion(trimmed)
        }
    }

    private func sendToNotion(_ text: String) {
        guard let notion = notion else {
            offlineQueue.enqueue(text)
            state = .idle
            return
        }
        notion.send(text: text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.playSound("Glass")
                    Notifier.notify(title: "노션 전송 완료 ✅", body: String(text.prefix(60)))
                case .failure(let error):
                    if error.isRetryable {
                        self.offlineQueue.enqueue(text)
                        Notifier.notify(title: "오프라인 — 임시 저장됨",
                                        body: "네트워크 연결 시 자동으로 재전송합니다.")
                    } else {
                        Notifier.notify(title: "전송 실패 ❌", body: error.userMessage)
                    }
                }
                self.state = .idle
            }
        }
    }

    // MARK: - Offline queue flushing

    private func flushQueue() {
        guard let notion = notion else { refreshUI(); return }
        let items = offlineQueue.load()
        guard !items.isEmpty else { refreshUI(); return }

        func sendNext(_ remaining: ArraySlice<OfflineQueue.Item>) {
            guard let first = remaining.first else {
                DispatchQueue.main.async { self.refreshUI() }
                return
            }
            notion.send(text: first.text) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.offlineQueue.remove(first)
                    DispatchQueue.main.async { self.refreshUI() }
                    sendNext(remaining.dropFirst())
                case .failure(let error):
                    if error.isRetryable {
                        // Still offline / server busy — stop and retry later.
                        DispatchQueue.main.async { self.refreshUI() }
                    } else {
                        // Permanent failure (e.g. bad token): drop so it can't block the queue.
                        self.offlineQueue.remove(first)
                        DispatchQueue.main.async { self.refreshUI() }
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
                self.isOnline = online
                if online && wasOffline {
                    self.flushQueue() // 네트워크 복구 시 자동 재전송
                }
            }
        }
        netMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Sound

    private func playSound(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
