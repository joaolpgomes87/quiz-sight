import AppKit
import Foundation
import Security

private enum CaptureResult {
    case image(Data, String)
    case cancelled
}

private enum DisplayState {
    case idle
    case capturing
    case analyzing
    case ready
    case failure(String)
}

// The color icon remains unchanged across all states.
private final class SelectionIndicator: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}

// The indicator must not intercept clicks on the capture icon.
private final class PassiveSpinner: NSProgressIndicator {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassiveStatusSymbol: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class SelectionSurface: NSView {
    var onSelected: ((NSRect) -> Void)?
    var onCancelled: (() -> Void)?
    private var firstPoint: NSPoint?
    private var lastPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let a = firstPoint, let b = lastPoint else { return }
        let rect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(a.x - b.x), height: abs(a.y - b.y))
        guard rect.width > 2, rect.height > 2 else { return }
        NSColor.secondaryLabelColor.withAlphaComponent(0.68).setStroke()
        let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: 2.5, yRadius: 2.5)
        outline.lineWidth = 1
        outline.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        firstPoint = point
        lastPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard firstPoint != nil else { return }
        lastPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let a = firstPoint else { return }
        let b = convert(event.locationInWindow, from: nil)
        firstPoint = nil
        lastPoint = nil
        needsDisplay = true
        let rect = NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(a.x - b.x), height: abs(a.y - b.y))
        guard rect.width >= 18, rect.height >= 18,
              let window = window else { onCancelled?(); return }
        let globalRect = window.convertToScreen(convert(rect, to: nil))
        onSelected?(globalRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancelled?() }
        else { super.keyDown(with: event) }
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// One transparent panel per display, without fill, text, or extra controls.
private final class SelectionCoordinator {
    private var panels: [SelectionPanel] = []
    private var escapeMonitor: Any?
    private var finished = false
    private let onFinished: (NSRect?) -> Void

    init(onFinished: @escaping (NSRect?) -> Void) {
        self.onFinished = onFinished
    }

    func begin() {
        for screen in NSScreen.screens {
            let panel = SelectionPanel(contentRect: screen.frame,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false, screen: screen)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = false
            panel.isMovable = false
            let surface = SelectionSurface(frame: NSRect(origin: .zero, size: screen.frame.size))
            surface.onSelected = { [weak self] rect in self?.finish(rect) }
            surface.onCancelled = { [weak self] in self?.finish(nil) }
            panel.contentView = surface
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        // A single click and drag on any display completes the selection.
        panels.first?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.finish(nil); return nil }
            return event
        }
    }

    private func finish(_ globalRect: NSRect?) {
        guard !finished else { return }
        finished = true
        if let monitor = escapeMonitor { NSEvent.removeMonitor(monitor) }
        escapeMonitor = nil
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        NSCursor.pop()
        onFinished(globalRect)
    }
}

// Transparent area detects hover without blocking status button clicks.
private final class StatusHoverOverlay: NSView {
    var onEnter: (() -> Void)?
    var onLeave: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { return nil }

    override func updateTrackingAreas() {
        if let previous = hoverArea { removeTrackingArea(previous) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onLeave?() }
}

// Clickable bubble, separate from the icon used to start a capture.
private final class PreviewView: NSVisualEffectView {
    var onEnter: (() -> Void)?
    var onLeave: (() -> Void)?
    var onClick: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let previous = hoverArea { removeTrackingArea(previous) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onLeave?() }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// Labels do not intercept clicks intended for the bubble.
private final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { return nil }
}

@objc final class QuizLensDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusHover: StatusHoverOverlay!
    private var selectionIndicator: SelectionIndicator!
    private var loadingIndicator: PassiveSpinner!
    private var readyIndicator: PassiveStatusSymbol!
    private var errorIndicator: PassiveStatusSymbol!
    private var selectionCoordinator: SelectionCoordinator?
    private var previewPanel: NSPanel!
    private var previewView: PreviewView!
    private var previewLabel: NSTextField!
    private var previewHint: NSTextField!
    private var detailsPopover: NSPopover!
    private var detailsHeading: NSTextField!
    private var detailsText: NSTextView!

    private var state: DisplayState = .idle
    private var latest: QuizResult?
    private var isCapturing = false
    private var generation = 0
    private var currentTask: URLSessionDataTask?
    private var pointerOnStatus = false
    private var pointerOnPreview = false
    private var hideToken = 0
    private let session = URLSession(configuration: .ephemeral)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        cleanupStaleCaptures()
        // Use the original full-color logo as a non-template NSImage.
        // Do not apply contentTintColor, which could remove the gradient.
        statusItem = NSStatusBar.system.statusItem(withLength: 45)
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = nil
        button.toolTip = nil
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // The status button draws the transparent image directly.
        let iconSize = NSSize(width: 20, height: 20)
        if let iconURL = Bundle.main.url(forResource: "QuizSightMenuBarColor", withExtension: "png"),
           let colorImage = NSImage(contentsOf: iconURL) {
            colorImage.size = iconSize
            colorImage.isTemplate = false
            button.image = colorImage
        } else if let iconURL = Bundle.main.url(forResource: "QuizSight-Icon", withExtension: "png"),
                  let colorImage = NSImage(contentsOf: iconURL) {
            colorImage.size = iconSize
            colorImage.isTemplate = false
            button.image = colorImage
        } else {
            button.image = NSImage(systemSymbolName: "viewfinder",
                                   accessibilityDescription: "QuizSight")
            NSLog("QuizSight: could not load the color icon from the bundle")
        }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .left
        button.contentTintColor = nil
        button.toolTip = "QuizSight — click to capture; hover to see the answer"

        let tracking = StatusHoverOverlay(frame: button.bounds)
        tracking.autoresizingMask = [.width, .height]
        tracking.onEnter = { [weak self] in
            self?.pointerOnStatus = true
            self?.showPreviewIfAppropriate()
        }
        tracking.onLeave = { [weak self] in
            self?.pointerOnStatus = false
            self?.schedulePreviewHide()
        }
        button.addSubview(tracking)
        statusHover = tracking

        let indicatorX: CGFloat = 31
        let centerY = button.bounds.midY

        let dot = SelectionIndicator(frame: NSRect(x: indicatorX + 4, y: centerY - 2,
                                                    width: 4, height: 4))
        dot.isHidden = true
        button.addSubview(dot)
        selectionIndicator = dot

        let spinner = PassiveSpinner(frame: NSRect(x: indicatorX, y: centerY - 6,
                                                    width: 12, height: 12))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        button.addSubview(spinner)
        loadingIndicator = spinner

        let ready = PassiveStatusSymbol(frame: NSRect(x: indicatorX, y: centerY - 6,
                                                       width: 12, height: 12))
        ready.imageScaling = .scaleProportionallyDown
        ready.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Answer available")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        ready.contentTintColor = .systemGreen
        ready.isHidden = true
        button.addSubview(ready)
        readyIndicator = ready

        // Use a subtle error indicator.
        let error = PassiveStatusSymbol(frame: NSRect(x: indicatorX, y: centerY - 6,
                                                       width: 12, height: 12))
        error.imageScaling = .scaleProportionallyDown
        error.image = NSImage(systemSymbolName: "exclamationmark",
                              accessibilityDescription: "Analysis failed")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        error.contentTintColor = .tertiaryLabelColor
        error.isHidden = true
        button.addSubview(error)
        errorIndicator = error

        configurePreview()
        configureDetails()
    }

    @objc private func statusClicked(_ sender: Any?) {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(with: event)
            return
        }
        startNewCapture()
    }

    @objc private func startNewCapture() {
        guard !isCapturing else { return }
        guard readAPIKey() != nil else {
            updateState(.failure("API key unavailable. Check Keychain access or try again."))
            return
        }

        generation += 1
        let runID = generation
        currentTask?.cancel()
        currentTask = nil
        isCapturing = true
        detailsPopover.close()
        hidePreview()
        updateState(.capturing)

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            guard let self = self, self.generation == runID else { return }
            let picker = SelectionCoordinator { [weak self] selection in
                guard let self = self, self.generation == runID else { return }
                self.selectionCoordinator = nil
                self.isCapturing = false
                guard let selection = selection else {
                    self.updateState(self.latest == nil ? .idle : .ready)
                    return
                }
                // Read geometry on the main thread; AppKit is not thread-safe.
                guard let primaryTop = NSScreen.screens.first?.frame.maxY else {
                    self.updateState(.failure("Could not identify the main display."))
                    return
                }
                // Hide the outline before capturing.
                self.updateState(.analyzing)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(110)) {
                    do {
                        let capture = try self.captureRegion(selection, primaryTop: primaryTop)
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, self.generation == runID else { return }
                            switch capture {
                            case .cancelled: self.updateState(self.latest == nil ? .idle : .ready)
                            case let .image(data, mime):
                                self.solveQuiz(image: data, mime: mime, runID: runID)
                            }
                        }
                    } catch {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, self.generation == runID else { return }
                            self.updateState(.failure("Capture failed: \(error.localizedDescription). Check Screen Recording permission."))
                        }
                    }
                }
            }
            self.selectionCoordinator = picker
            picker.begin()
        }
    }

    // AppKit uses a bottom-left origin; screencapture -R uses the main display’s top-left origin.
    private func captureRegion(_ rectangle: NSRect, primaryTop: CGFloat) throws -> CaptureResult {
        let x = Int(floor(rectangle.minX))
        let y = Int(floor(primaryTop - rectangle.maxY))
        let width = Int(ceil(rectangle.maxX)) - x
        let height = Int(ceil(primaryTop - rectangle.minY)) - y
        guard width >= 18, height >= 18 else { return .cancelled }

        cleanupStaleCaptures()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quizsight-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("capture.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", "\(x),\(y),\(width),\(height)", "-t", "png", file.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: file.path) else { return .cancelled }

        let png = try Data(contentsOf: file)
        guard png.count > 500 else { return .cancelled }
        // Preserve small text and diagrams without lossy JPEG compression.
        return .image(png, "image/png")
    }

    private func cleanupStaleCaptures() {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let entries = try? manager.contentsOfDirectory(at: manager.temporaryDirectory,
                                                              includingPropertiesForKeys: Array(keys)) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries {
            let name = entry.lastPathComponent
            let prefix = "quizsight-capture-"
            let oldPrefix = "quizlens-"
            let isCaptureDirectory = name.hasPrefix(prefix) &&
                UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
            let isLegacyCapture = name.hasPrefix(oldPrefix) && name.hasSuffix(".png") &&
                UUID(uuidString: String(name.dropFirst(oldPrefix.count).dropLast(4))) != nil
            guard isCaptureDirectory || isLegacyCapture,
                  let properties = try? entry.resourceValues(forKeys: keys),
                  properties.isSymbolicLink != true,
                  properties.isDirectory == isCaptureDirectory,
                  let modified = properties.contentModificationDate, modified < cutoff else { continue }
            try? manager.removeItem(at: entry)
        }
    }

    private func solveQuiz(image: Data, mime: String, runID: Int) {
        guard let key = readAPIKey() else {
            fail("API key missing.", runID: runID)
            return
        }

        let prompt = """
        Answer the quiz or exercise questions visible in the image in English.
        Read the entire question and every visible option carefully, including negations,
        qualifiers, numbers and diagrams. Solve each question in the order shown and check
        that the selected answer matches both the question and its printed option label.
        Give a concise explanation of why the answer fits. Do not invent missing text.
        IMPORTANT: only fill in "label" if a letter (A, B, C, D...) or number (1, 2, 3...)
        is actually printed beside the option in the image. In that case, "label" contains
        only that letter or number, and "answer" contains the selected option text.
        If the options have no letters or numbers, leave "label" empty and put the full
        selected option text in "answer". If the question has no options, write the answer
        in "answer" (one sentence if possible) and leave "label" empty.
        If the image is incomplete or unreadable, or you cannot determine an answer,
        do not guess: set label="", answer="?" and explain the limitation in "why".
        If there are no questions, return answers=[].
        Respond ONLY with valid JSON in this format:
        {"answers":[{"question":"1","label":"B","answer":"full option text or answer","why":"one-sentence explanation","confidence":"medium"}],"note":""}
        confidence = "high", "medium", or "low"; use low when the answer is uncertain.
        """
        let payload: [String: Any] = [
            "model": readModel(),
            "store": false,
            "input": [[
                "role": "user",
                "content": [
                    ["type": "input_text", "text": prompt],
                    ["type": "input_image",
                     "image_url": "data:\(mime);base64,\(image.base64EncodedString())",
                     "detail": "high"]
                ]
            ]],
            "text": ["format": ["type": "json_object"]],
            "max_output_tokens": 850
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else {
            fail("Could not prepare the API request.", runID: runID)
            return
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.httpBody = json
        request.timeoutInterval = 40
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                self.fail("Connection failed: \(error.localizedDescription)", runID: runID)
                return
            }
            guard let data = data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.fail("The API returned invalid data.", runID: runID)
                return
            }
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                let message = (object["error"] as? [String: Any])?["message"] as? String
                self.fail("API error \(http.statusCode): \(message ?? "Check your API key, balance, and model access.")", runID: runID)
                return
            }
            let output = (object["output"] as? [[String: Any]] ?? []).flatMap { item -> [String] in
                (item["content"] as? [[String: Any]] ?? []).compactMap { part -> String? in
                    guard part["type"] as? String == "output_text" else { return nil }
                    return part["text"] as? String
                }
            }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                self.fail("The AI returned no answer. Include the question and options in the capture.", runID: runID)
                return
            }
            let result = QuizResult.parse(output)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.generation == runID else { return }
                self.currentTask = nil
                self.latest = result
                if result.answers.isEmpty {
                    self.updateState(.failure(result.note.isEmpty ? "No questions were identified." : result.note))
                } else {
                    self.updateState(.ready)
                }
            }
        }
        currentTask = task
        task.resume()
    }

    private func fail(_ message: String, runID: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.generation == runID else { return }
            self.currentTask = nil
            self.updateState(.failure(message))
        }
    }

    private func updateState(_ next: DisplayState) {
        state = next
        // The logo remains unchanged; only the indicator on the right changes.
        selectionIndicator.isHidden = true
        readyIndicator.isHidden = true
        errorIndicator.isHidden = true
        loadingIndicator.stopAnimation(nil)
        loadingIndicator.isHidden = true

        switch next {
        case .idle: break
        case .capturing:
            selectionIndicator.isHidden = false
        case .analyzing:
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
        case .ready:
            readyIndicator.isHidden = false
        case .failure:
            errorIndicator.isHidden = false
        }

        // Only show the bubble on hover, not simply when the API responds.
        // Update the visible bubble if the pointer is already over the icon.
        if previewPanel.isVisible {
            if pointerOnStatus || pointerOnPreview { showPreviewIfAppropriate() }
            else { hidePreview() }
        }
    }

    private func readAPIKey() -> String? {
        let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let env = env, !env.isEmpty { return env }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.quizsight.openai-api-key",
            kSecAttrAccount as String: "openai"
        ]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data,
           let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }
        guard status == errSecItemNotFound else {
            showKeyError("Could not read the API key from Keychain (error \(status)).")
            return nil
        }

        let legacyFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quizlens_api_key")
        let legacyKey = (try? String(contentsOf: legacyFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key: String
        if let legacyKey = legacyKey, !legacyKey.isEmpty {
            key = legacyKey
        } else {
            let alert = NSAlert()
            alert.messageText = "OpenAI API key"
            alert.informativeText = "Enter your API key. QuizSight will save it in your macOS Keychain."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            alert.accessoryView = input
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            key = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
        }

        var newItem = query
        newItem[kSecValueData as String] = Data(key.utf8)
        let saveStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard saveStatus == errSecSuccess else {
            showKeyError("Could not save the API key in Keychain (error \(saveStatus)).")
            return nil
        }
        if let legacyKey = legacyKey, !legacyKey.isEmpty {
            do {
                try FileManager.default.removeItem(at: legacyFile)
            } catch {
                showKeyError("The key was saved in Keychain, but the old key file could not be removed. Delete ~/.quizlens_api_key manually.")
            }
        }
        return key
    }

    private func showKeyError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "QuizSight Keychain"
        alert.informativeText = message
        alert.runModal()
    }

    private func readModel() -> String {
        let defaultModel = "gpt-5.4-mini"
        let modelFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quizlens_model")
        guard let contents = try? String(contentsOf: modelFile, encoding: .utf8) else {
            return defaultModel
        }
        let model = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? defaultModel : model
    }

    // MARK: - Hover bubble: only visible while the pointer is over the icon.

    private func configurePreview() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 90),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false

        let root = PreviewView(frame: NSRect(x: 0, y: 0, width: 340, height: 90))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        root.onEnter = { [weak self] in
            self?.pointerOnPreview = true
            self?.hideToken += 1
        }
        root.onLeave = { [weak self] in
            self?.pointerOnPreview = false
            self?.schedulePreviewHide()
        }
        root.onClick = { [weak self] in self?.showDetails() }

        let answer = PassthroughLabel(wrappingLabelWithString: "")
        answer.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        answer.textColor = .labelColor
        answer.maximumNumberOfLines = 8
        answer.lineBreakMode = .byWordWrapping
        answer.isSelectable = false
        root.addSubview(answer)

        let hint = PassthroughLabel(labelWithString: "Click here for details")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        root.addSubview(hint)

        panel.contentView = root
        previewPanel = panel
        previewView = root
        previewLabel = answer
        previewHint = hint
    }

    private func previewMessage() -> String {
        switch state {
        case .idle: return "Click the icon to select a question."
        case .capturing: return "Select the question and options on screen."
        case .analyzing: return "Analyzing capture…"
        case .ready: return latest?.hoverSummary ?? "No answer available."
        case .failure(let message): return "Could not analyze: \(message)"
        }
    }

    private func showPreviewIfAppropriate() {
        // Only show the result or error when the user hovers over the indicator.
        switch state {
        case .ready, .failure: break
        default:
            if previewPanel.isVisible { hidePreview() }
            return
        }
        guard (pointerOnStatus || pointerOnPreview), !detailsPopover.isShown,
              let button = statusItem.button, let window = button.window else { return }

        let message = previewMessage()
        let width: CGFloat = message.count < 45 ? 290 : 420
        let contentWidth = width - 28
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let bound = (message as NSString).boundingRect(
            with: NSSize(width: contentWidth, height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font], context: nil)
        let textHeight = min(CGFloat(175), max(CGFloat(20), ceil(bound.height) + 4))
        let height = max(CGFloat(63), textHeight + 37)
        let size = NSSize(width: width, height: height)

        previewPanel.setContentSize(size)
        previewView.frame = NSRect(origin: .zero, size: size)
        previewLabel.frame = NSRect(x: 14, y: 31, width: contentWidth, height: height - 42)
        previewLabel.stringValue = message
        previewHint.frame = NSRect(x: 14, y: 9, width: contentWidth, height: 15)

        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? rect
        // A two-point overlap makes it easier to move the pointer to the bubble.
        let x = min(max(rect.midX - width / 2, visible.minX + 6), visible.maxX - width - 6)
        let y = max(visible.minY + 6, rect.minY - height + 2)
        previewPanel.setFrameOrigin(NSPoint(x: x, y: y))
        previewPanel.orderFrontRegardless()
    }

    private func hidePreview() {
        hideToken += 1
        pointerOnPreview = false
        previewPanel.orderOut(nil)
    }

    private func schedulePreviewHide() {
        hideToken += 1
        let token = hideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(220)) { [weak self] in
            guard let self = self, self.hideToken == token,
                  !self.pointerOnStatus, !self.pointerOnPreview else { return }
            self.previewPanel.orderOut(nil)
        }
    }

    // MARK: - Details panel, opened from the bubble or menu.

    private func configureDetails() {
        let width: CGFloat = 372
        let height: CGFloat = 235
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: width, height: height)

        let controller = NSViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let heading = NSTextField(labelWithString: "QuizSight")
        heading.font = NSFont.boldSystemFont(ofSize: 14)
        heading.frame = NSRect(x: 16, y: height - 33, width: width - 32, height: 21)
        root.addSubview(heading)
        detailsHeading = heading

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 47, width: width - 32, height: height - 85))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.frame.size))
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.font = NSFont.systemFont(ofSize: 12)
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 2, height: 5)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        root.addSubview(scroll)
        detailsText = text

        let newCapture = NSButton(title: "New capture", target: self,
                                  action: #selector(startNewCapture))
        newCapture.bezelStyle = .rounded
        newCapture.frame = NSRect(x: 16, y: 10, width: 125, height: 28)
        root.addSubview(newCapture)

        let close = NSButton(title: "Close", target: self, action: #selector(closeDetails))
        close.bezelStyle = .rounded
        close.frame = NSRect(x: width - 100, y: 10, width: 84, height: 28)
        root.addSubview(close)

        controller.view = root
        popover.contentViewController = controller
        detailsPopover = popover
    }

    @objc private func showDetails() {
        hidePreview()
        var title = "QuizSight — details"
        var body = "Click the icon to select a question."
        switch state {
        case .ready:
            title = "Suggested answer"
            body = latest?.detailText ?? body
        case .failure(let message):
            title = "Analysis error"
            body = message
        case .analyzing:
            title = "Analyzing…"
            body = "Hover over the icon to see the result."
        case .capturing:
            body = "Select the question and options on screen."
        case .idle: break
        }
        detailsHeading.stringValue = title
        detailsText.string = body
        detailsText.scrollToBeginningOfDocument(nil)
        if let button = statusItem.button, !detailsPopover.isShown {
            detailsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func closeDetails() { detailsPopover.close() }

    private func showContextMenu(with event: NSEvent) {
        guard let button = statusItem.button else { return }
        hidePreview()
        let menu = NSMenu()
        let capture = NSMenuItem(title: "New capture", action: #selector(startNewCapture), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        let details = NSMenuItem(title: "View details", action: #selector(showDetails), keyEquivalent: "")
        details.target = self
        menu.addItem(details)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit QuizSight", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func quitApp() {
        currentTask?.cancel()
        session.invalidateAndCancel()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = QuizLensDelegate()
app.delegate = delegate
app.run()
