import AppKit
import AVFoundation
import Carbon
import CoreGraphics
import ScreenCaptureKit

// Local-only recorder: Apple frameworks, no network client or third-party runtime.
final class CaptureMonitor: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var systemPackets = 0
    private var microphonePackets = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(buffer), CMSampleBufferGetNumSamples(buffer) > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        if type == .audio { systemPackets += 1 }
        if type == .microphone { microphonePackets += 1 }
    }

    func counts() -> (system: Int, microphone: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (systemPackets, microphonePackets)
    }
}

enum Phase { case idle, preparing, recording, saving }

private enum RecorderShortcut {
    static let modifiers = UInt32(controlKey | shiftKey)
    static let recording = "Control + Shift + R"
    static let showControls = "Control + Shift + S"
}

@MainActor
final class RecorderAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
    SCContentSharingPickerObserver, SCStreamDelegate, SCRecordingOutputDelegate {
    private var phase: Phase = .idle
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var startButton: NSButton!
    private var stopButton: NSButton!
    private var selectButton: NSButton!
    private var folderButton: NSButton!
    private var systemCheck: NSButton!
    private var micCheck: NSButton!
    private var microphonePicker: NSPopUpButton!
    private var fpsPicker: NSPopUpButton!
    private var sizePicker: NSPopUpButton!
    private var targetLabel: NSTextField!
    private var folderLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var clockLabel: NSTextField!
    private var phaseLabel: NSTextField!
    private var modeLabel: NSTextField!
    private var menuRecord: NSMenuItem!
    private var menuMicrophone: NSMenuItem!
    private var filter: SCContentFilter?
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var monitor: CaptureMonitor?
    private var recordingURL: URL?
    private var lastURL: URL?
    private var selectedMicIDs: [String] = []
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var hotKeyRegistrationResults: [String: Int32] = [:]
    private var hotKeyTestEvents: [String: Int] = [:]
    private var eventHandler: EventHandlerRef?
    private var timer: Timer?
    private var startedAt: Date?
    private var recordSystem = true
    private var recordMicrophone = false
    private var waitingToQuit = false
    private var failure: String?
    private var destination: URL {
        let saved = UserDefaults.standard.string(forKey: "recordingDirectory")
        return saved.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("本机录屏", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon1024", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = icon }
        buildMenu()
        buildWindow()
        setupStatusItem()
        registerHotKeys()
        SCContentSharingPicker.shared.add(self)
        updateControls()
        showWindow()
        if CommandLine.arguments.contains("--diagnostics") || CommandLine.arguments.contains("--hotkey-test") { writeDiagnostics() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard phase != .idle else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "退出前保存录制？"
        alert.informativeText = "停止录制并等待视频写入完成后退出。"
        alert.addButton(withTitle: "保存并退出")
        alert.addButton(withTitle: "继续录制")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        waitingToQuit = true
        if phase == .recording { stopRecording() }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func label(_ text: String, size: CGFloat = 13, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = StudioPalette.font(size)
        field.textColor = secondary ? StudioPalette.muted : StudioPalette.ink
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "本机录屏"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = StudioPalette.canvas
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 48)
        ])
        func spacer() -> NSView {
            let view = NSView()
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            return view
        }
        func full(_ view: NSView, height: CGFloat) {
            root.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
            view.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
        func card(_ content: NSView, height: CGFloat) {
            let panel = StudioPanel()
            content.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
                content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
                content.centerYAnchor.constraint(equalTo: panel.centerYAnchor)
            ])
            full(panel, height: height)
        }
        func column(_ views: [NSView], spacing: CGFloat = 4) -> NSStackView {
            let stack = NSStackView(views: views)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = spacing
            return stack
        }

        let icon = NSImageView()
        if let url = Bundle.main.url(forResource: "AppIcon1024", withExtension: "png") {
            icon.image = NSImage(contentsOf: url)
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 46).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 46).isActive = true
        let title = label("本机录屏", size: 25)
        title.font = StudioPalette.font(25, weight: .semibold)
        let caption = label("SCREEN  /  SOUND  /  LOCAL", size: 10, secondary: true)
        caption.font = NSFont(name: "AvenirNext-DemiBold", size: 10)
        let privacy = label("仅在本机 · 无需账号", size: 11, secondary: true)
        full(row([icon, column([title, caption], spacing: 1), spacer(), privacy]), height: 46)

        let deck = StudioPanel(color: StudioPalette.deck, radius: 18, bordered: false)
        phaseLabel = label("●  待机", size: 11)
        phaseLabel.font = StudioPalette.font(11, weight: .semibold)
        phaseLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        clockLabel = label("00:00", size: 40)
        clockLabel.font = NSFont(name: "AvenirNext-Medium", size: 40) ?? .monospacedDigitSystemFont(ofSize: 40, weight: .medium)
        clockLabel.textColor = StudioPalette.paper
        modeLabel = label("画面 + 系统声音\n麦克风未开启", size: 12)
        modeLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        modeLabel.maximumNumberOfLines = 2
        modeLabel.lineBreakMode = .byWordWrapping
        for view in [phaseLabel!, clockLabel!, modeLabel!] {
            view.translatesAutoresizingMaskIntoConstraints = false
            deck.addSubview(view)
        }
        NSLayoutConstraint.activate([
            phaseLabel.leadingAnchor.constraint(equalTo: deck.leadingAnchor, constant: 22),
            phaseLabel.topAnchor.constraint(equalTo: deck.topAnchor, constant: 15),
            clockLabel.leadingAnchor.constraint(equalTo: deck.leadingAnchor, constant: 21),
            clockLabel.bottomAnchor.constraint(equalTo: deck.bottomAnchor, constant: -12),
            modeLabel.trailingAnchor.constraint(equalTo: deck.trailingAnchor, constant: -22),
            modeLabel.centerYAnchor.constraint(equalTo: deck.centerYAnchor),
            modeLabel.widthAnchor.constraint(equalToConstant: 190)
        ])
        full(deck, height: 98)

        selectButton = StudioButton("选择画面…", target: self, action: #selector(selectContent))
        targetLabel = label("主屏幕（默认）", size: 13)
        targetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let source = column([label("录制画面", size: 10, secondary: true), targetLabel])
        source.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card(row([source, spacer(), selectButton]), height: 64)

        systemCheck = AudioTile("系统声音", detail: "直接录下电脑正在播放的声音", symbol: "speaker.wave.2.fill", target: self, action: #selector(settingsChanged))
        systemCheck.state = .on
        micCheck = AudioTile("麦克风（人声）", detail: "需要讲解时，再打开这一项", symbol: "mic.fill", target: self, action: #selector(settingsChanged))
        micCheck.state = .off
        let audioRow = row([systemCheck, micCheck])
        audioRow.distribution = .fillEqually
        audioRow.heightAnchor.constraint(equalToConstant: 72).isActive = true
        microphonePicker = NSPopUpButton()
        microphonePicker.font = StudioPalette.font(11)
        microphonePicker.addItem(withTitle: "系统默认麦克风")
        selectedMicIDs = [""]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                       mediaType: .audio, position: .unspecified).devices
        for device in devices {
            microphonePicker.addItem(withTitle: device.localizedName)
            selectedMicIDs.append(device.uniqueID)
        }
        let inputRow = row([label("输入设备", size: 11, secondary: true), microphonePicker, spacer()])
        microphonePicker.widthAnchor.constraint(equalToConstant: 230).isActive = true
        let audioGroup = column([audioRow, inputRow], spacing: 7)
        audioRow.widthAnchor.constraint(equalTo: audioGroup.widthAnchor).isActive = true
        inputRow.widthAnchor.constraint(equalTo: audioGroup.widthAnchor).isActive = true
        full(audioGroup, height: 104)

        fpsPicker = NSPopUpButton()
        fpsPicker.font = StudioPalette.font(12)
        fpsPicker.addItems(withTitles: ["30 fps", "60 fps"])
        sizePicker = NSPopUpButton()
        sizePicker.font = StudioPalette.font(12)
        sizePicker.addItems(withTitles: ["1080p 内按比例", "原始分辨率"])
        sizePicker.widthAnchor.constraint(equalToConstant: 195).isActive = true
        fpsPicker.widthAnchor.constraint(equalToConstant: 95).isActive = true
        card(row([label("画质", size: 12, secondary: true), sizePicker, spacer(), label("帧率", size: 12, secondary: true), fpsPicker]), height: 50)

        folderButton = StudioButton("更改位置…", target: self, action: #selector(chooseFolder), style: .quiet)
        folderLabel = label(destination.path, size: 11, secondary: true)
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let storage = column([label("保存到", size: 10, secondary: true), folderLabel])
        storage.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card(row([storage, spacer(), folderButton]), height: 54)

        startButton = StudioButton("●  开始录制", target: self, action: #selector(startRecording), style: .primary)
        startButton.font = StudioPalette.font(15, weight: .semibold)
        stopButton = StudioButton("■  停止并保存", target: self, action: #selector(stopRecording))
        stopButton.font = StudioPalette.font(14, weight: .semibold)
        let controls = row([startButton, stopButton])
        controls.distribution = .fillEqually
        full(controls, height: 46)
        startButton.heightAnchor.constraint(equalTo: controls.heightAnchor).isActive = true
        stopButton.heightAnchor.constraint(equalTo: controls.heightAnchor).isActive = true

        statusLabel = label("准备就绪。按下开始，记录画面与声音。", size: 11, secondary: true)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        full(statusLabel, height: 34)
        let links = row([
            StudioButton("打开录制文件夹 ↗", target: self, action: #selector(openFolder), style: .quiet),
            StudioButton("查看最近视频 ↗", target: self, action: #selector(revealLast), style: .quiet),
            spacer()
        ])
        let shortcuts = label("\(RecorderShortcut.recording)  开始 / 停止   ·   \(RecorderShortcut.showControls)  显示窗口", size: 11, secondary: true)
        let footer = column([links, shortcuts], spacing: 4)
        full(footer, height: 58)
        window.setContentSize(NSSize(width: 640, height: root.fittingSize.height + 70))
        window.center()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "显示本机录屏", action: #selector(showWindow), keyEquivalent: "0").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出本机录屏", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "本机录屏")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "显示控制窗口", action: #selector(showWindow), keyEquivalent: "").target = self
        menuRecord = menu.addItem(withTitle: "开始录制  \(RecorderShortcut.recording)", action: #selector(toggleRecording), keyEquivalent: "")
        menuRecord.target = self
        menuMicrophone = menu.addItem(withTitle: "录制麦克风（人声）", action: #selector(toggleMicrophone), keyEquivalent: "")
        menuMicrophone.target = self
        menu.addItem(withTitle: "打开录制文件夹", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu
    }

    private func registerHotKeys() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let parameterStatus = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard parameterStatus == noErr, key.signature == 0x4C524543 else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<RecorderAppDelegate>.fromOpaque(context).takeUnretainedValue()
            let id = key.id
            DispatchQueue.main.async { delegate.handleHotKey(id) }
            return noErr
        }
        let target = GetEventDispatcherTarget()
        let handlerStatus = InstallEventHandler(target, callback, 1, &event,
                                               Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        hotKeyRegistrationResults["event_handler"] = handlerStatus
        for (id, code) in [(UInt32(1), UInt32(kVK_ANSI_R)), (UInt32(2), UInt32(kVK_ANSI_S))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(code, RecorderShortcut.modifiers,
                                            EventHotKeyID(signature: 0x4C524543, id: id),
                                            target, OptionBits(kEventHotKeyExclusive), &ref)
            hotKeyRefs.append(ref)
            hotKeyRegistrationResults[id == 1 ? RecorderShortcut.recording : RecorderShortcut.showControls] = result
            if result != noErr { statusLabel.stringValue = "快捷键被其他程序占用，请使用按钮（错误 \(result)）" }
        }
    }

    private func handleHotKey(_ id: UInt32) {
        // Explicit maintenance mode checks dispatch without recording the user's desktop.
        if CommandLine.arguments.contains("--hotkey-test") {
            let name = id == 1 ? RecorderShortcut.recording : RecorderShortcut.showControls
            hotKeyTestEvents[name, default: 0] += 1
            writeDiagnostics()
            if id == 1 {
                statusLabel.stringValue = "已识别 \(name)；快捷键测试模式不会开始录制。"
                return
            }
        }
        if id == 1 { toggleRecording() }
        if id == 2 { showWindow() }
    }

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func settingsChanged() { updateControls() }
    @objc private func toggleMicrophone() {
        guard phase == .idle else { return }
        micCheck.state = micCheck.state == .on ? .off : .on
        updateControls()
    }

    private func updateControls() {
        let idle = phase == .idle
        startButton.isEnabled = idle
        stopButton.isEnabled = phase == .recording
        selectButton.isEnabled = idle
        folderButton.isEnabled = idle
        systemCheck.isEnabled = idle
        micCheck.isEnabled = idle
        microphonePicker.isEnabled = idle && micCheck.state == .on
        fpsPicker.isEnabled = idle
        sizePicker.isEnabled = idle
        menuRecord.title = (phase == .recording ? "停止并保存  " : "开始录制  ") + RecorderShortcut.recording
        menuRecord.isEnabled = idle || phase == .recording
        menuMicrophone.state = micCheck.state
        menuMicrophone.isEnabled = idle
        systemCheck.needsDisplay = true
        micCheck.needsDisplay = true
        startButton.needsDisplay = true
        stopButton.needsDisplay = true
        phaseLabel.stringValue = phase == .recording ? "●  正在录制" : phase == .preparing ? "●  正在准备" : phase == .saving ? "●  正在保存" : "●  待机"
        phaseLabel.textColor = phase == .recording ? StudioPalette.coral : NSColor.white.withAlphaComponent(0.6)
        modeLabel.stringValue = "画面" + (systemCheck.state == .on ? " + 系统声音" : " · 不录系统声音") + "\n" + (micCheck.state == .on ? "麦克风已开启" : "麦克风未开启")
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择保存位置"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: "recordingDirectory")
        folderLabel.stringValue = destination.path
    }

    @objc private func openFolder() {
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            NSWorkspace.shared.open(destination)
        } catch { fail("无法打开保存位置：\(error.localizedDescription)") }
    }

    @objc private func revealLast() {
        guard let lastURL else { openFolder(); return }
        NSWorkspace.shared.activateFileViewerSelecting([lastURL])
    }

    @objc private func selectContent() {
        guard phase == .idle else { return }
        let picker = SCContentSharingPicker.shared
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleDisplay, .singleWindow, .singleApplication]
        config.allowsChangingSelectedContent = false
        picker.defaultConfiguration = config
        picker.isActive = true
        picker.present()
        statusLabel.stringValue = "请选择屏幕、窗口或应用；选择后按“开始录制”"
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.statusLabel.stringValue = "选择已取消，仍使用原录制对象" }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            guard self.phase == .idle else { return }
            self.filter = filter
            let size = filter.contentRect.size
            self.targetLabel.stringValue = "已选择画面（\(Int(size.width)) × \(Int(size.height))）"
            self.statusLabel.stringValue = "准备就绪，选择本身不会开始录制"
            self.showWindow()
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in self.fail("无法选择画面：\(error.localizedDescription)") }
    }

    @objc private func toggleRecording() {
        if phase == .idle { startRecording() }
        else if phase == .recording { stopRecording() }
    }

    @objc private func startRecording() {
        guard phase == .idle else { return }
        phase = .preparing
        failure = nil
        recordSystem = systemCheck.state == .on
        recordMicrophone = micCheck.state == .on
        updateControls()
        statusLabel.stringValue = "正在准备录制…"
        Task { await prepareAndStart() }
    }

    private func prepareAndStart() async {
        do {
            // The system picker can authorize its selected target without broad desktop access.
            if filter == nil && !CGPreflightScreenCaptureAccess() {
                guard CGRequestScreenCaptureAccess() else {
                    throw NSError(domain: "LocalRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "请在系统设置的“隐私与安全性 → 屏幕与系统音频录制”中授权本机录屏，或用“选择画面”授权指定窗口。授权后再次开始。"])
                }
            }
            if recordMicrophone {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard granted else {
                    throw NSError(domain: "LocalRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey:
                        "麦克风尚未授权，本次没有开始录制。请授权麦克风，或取消“麦克风（人声）”选项。"])
                }
            }
            let target: SCContentFilter
            if let filter { target = filter }
            else {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                    throw NSError(domain: "LocalRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: "没有可录制的屏幕"])
                }
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                target = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let values = try destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let free = values.volumeAvailableCapacityForImportantUsage, free < 500_000_000 {
                throw NSError(domain: "LocalRecorder", code: 4, userInfo: [NSLocalizedDescriptionKey: "保存磁盘剩余空间不足 500MB，请更换保存位置"])
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let url = destination.appendingPathComponent("录屏_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6)).mp4")
            let config = SCStreamConfiguration()
            let scale = CGFloat(target.pointPixelScale)
            var width = target.contentRect.width * scale
            var height = target.contentRect.height * scale
            guard width > 0, height > 0 else {
                throw NSError(domain: "LocalRecorder", code: 5, userInfo: [NSLocalizedDescriptionKey: "选择的画面尺寸无效，请重新选择"])
            }
            if sizePicker.indexOfSelectedItem == 0 {
                let factor = min(1, min(1920 / width, 1080 / height))
                width *= factor; height *= factor
            }
            config.width = max(2, Int(width) / 2 * 2)
            config.height = max(2, Int(height) / 2 * 2)
            config.minimumFrameInterval = CMTime(value: 1, timescale: fpsPicker.indexOfSelectedItem == 0 ? 30 : 60)
            config.queueDepth = 6
            config.showsCursor = true
            config.capturesAudio = recordSystem
            config.captureMicrophone = recordMicrophone
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            if recordMicrophone {
                let index = microphonePicker.indexOfSelectedItem
                if index > 0, index < selectedMicIDs.count { config.microphoneCaptureDeviceID = selectedMicIDs[index] }
            }
            let outConfig = SCRecordingOutputConfiguration()
            outConfig.outputURL = url
            outConfig.videoCodecType = .h264
            outConfig.outputFileType = .mp4
            let output = SCRecordingOutput(configuration: outConfig, delegate: self)
            let capture = SCStream(filter: target, configuration: config, delegate: self)
            let monitor = CaptureMonitor()
            let queue = DispatchQueue(label: "local-recorder.audio-monitor")
            if recordSystem { try capture.addStreamOutput(monitor, type: .audio, sampleHandlerQueue: queue) }
            if recordMicrophone { try capture.addStreamOutput(monitor, type: .microphone, sampleHandlerQueue: queue) }
            try capture.addRecordingOutput(output)
            self.stream = capture; self.output = output; self.monitor = monitor; self.recordingURL = url
            try await capture.startCapture()
            // Only recordingOutputDidStartRecording changes the UI to Recording.
        } catch { fail(error.localizedDescription) }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [self] in
            guard self.output === recordingOutput, self.phase == .preparing else { return }
            self.phase = .recording
            self.startedAt = Date()
            self.statusLabel.stringValue = "正在录制 · 系统声音\(self.recordSystem ? "开" : "关") · 麦克风\(self.recordMicrophone ? "开" : "关")"
            self.statusItem.button?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "正在录制")
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateClock() }
            }
            self.updateControls()
            if self.waitingToQuit { self.stopRecording() }
        }
    }

    private func updateClock() {
        let seconds = Int(output.map { CMTimeGetSeconds($0.recordedDuration) } ?? 0)
        clockLabel.stringValue = String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
        statusItem.button?.title = " " + clockLabel.stringValue
        if let capacity = try? destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           capacity < 250_000_000 { statusLabel.stringValue = "磁盘空间不足，正在停止并保存"; stopRecording() }
    }

    @objc private func stopRecording() {
        guard phase == .recording, let stream else { return }
        phase = .saving
        timer?.invalidate(); timer = nil
        statusLabel.stringValue = "正在停止并保存，请稍候…"
        updateControls()
        Task {
            do { try await stream.stopCapture() }
            catch { fail("停止录制失败：\(error.localizedDescription)") }
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard self.output === recordingOutput else { return }
            await self.validateAndFinish()
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.output === recordingOutput else { return }
            self.fail("视频写入失败：\(error.localizedDescription)")
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            self.failure = "录制被中断：\(error.localizedDescription)"
            self.phase = .saving
            self.timer?.invalidate(); self.timer = nil
            self.statusLabel.stringValue = self.failure! + "；正在等待文件完成写入"
            self.updateControls()
        }
    }

    private func validateAndFinish() async {
        guard let url = recordingURL else { fail("输出文件位置丢失"); return }
        phase = .saving
        updateControls()
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let videos = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard CMTimeGetSeconds(duration) > 0, !videos.isEmpty else {
                throw NSError(domain: "LocalRecorder", code: 6, userInfo: [NSLocalizedDescriptionKey: "文件没有有效的视频或时长"])
            }
            let counts = monitor?.counts() ?? (system: 0, microphone: 0)
            var warnings: [String] = []
            if let failure { warnings.append(failure) }
            if recordSystem && counts.system == 0 { warnings.append("未收到系统声音数据") }
            if recordMicrophone && counts.microphone == 0 { warnings.append("未收到麦克风数据") }
            if (recordSystem || recordMicrophone) && audio.isEmpty { warnings.append("输出文件没有音轨") }
            let report: [String: Any] = [
                "file": url.lastPathComponent, "duration_seconds": CMTimeGetSeconds(duration),
                "video_tracks": videos.count, "audio_tracks": audio.count,
                "system_audio_enabled": recordSystem, "microphone_enabled": recordMicrophone,
                "system_audio_packets": counts.system, "microphone_packets": counts.microphone,
                "warnings": warnings, "status": warnings.isEmpty ? "saved" : "saved_with_warning"
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
            lastURL = url
            let status = warnings.isEmpty ? "已保存：\(url.lastPathComponent)" : "已保存，但需检查：" + warnings.joined(separator: "；")
            reset(status)
            if !warnings.isEmpty { showWindow() }
        } catch { fail("保存后检查失败：\(error.localizedDescription)。录制文件保留在 \(url.path)") }
    }

    private func fail(_ message: String) {
        let active = stream
        reset("未完成：" + message)
        if let active { Task { try? await active.stopCapture() } }
        if !waitingToQuit { showWindow() }
    }

    private func reset(_ message: String) {
        timer?.invalidate(); timer = nil
        phase = .idle
        stream = nil; output = nil; monitor = nil; recordingURL = nil; startedAt = nil
        statusLabel.stringValue = message
        statusItem.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "本机录屏")
        statusItem.button?.title = ""
        updateControls()
        if waitingToQuit { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    private func writeDiagnostics() {
        let report: [String: Any] = [
            "mode": CommandLine.arguments.contains("--hotkey-test") ? "hotkey_test_no_capture" : "idle_ui_diagnostics",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "screen_recording_authorized": CGPreflightScreenCaptureAccess(),
            "microphone_authorization": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
            "hotkey_registration_count": hotKeyRefs.compactMap { $0 }.count,
            "hotkey_registration_results": hotKeyRegistrationResults,
            "hotkey_test_events": hotKeyTestEvents,
            "capture_started": phase == .recording || phase == .saving, "destination": destination.path
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("local-screen-recorder-diagnostics.json"), options: .atomic)
        }
    }
}

@main
enum Entry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = RecorderAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
