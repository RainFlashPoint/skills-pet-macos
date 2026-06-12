import AppKit

final class AIModelSettingsWindowController: NSWindowController {
    private let store = AIModelSettingsStore.shared

    private let enabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let providerPopup = NSPopUpButton()
    private let qualityPopup = NSPopUpButton()
    private let modelField = NSTextField()
    private let endpointField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("AI 模型设置", "AI Model Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.82, alpha: 1)

        super.init(window: window)
        window.contentView = buildContentView()
        window.center()
        loadSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.82, alpha: 1).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 18
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])

        stack.addArrangedSubview(headerView())
        stack.addArrangedSubview(settingsCard())
        stack.addArrangedSubview(footerView())
        return root
    }

    private func headerView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading

        let eyebrow = NSTextField(labelWithString: L("模型配置", "MODEL CONFIGURATION"))
        eyebrow.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.16, alpha: 1)
        stack.addArrangedSubview(eyebrow)

        let title = NSTextField(labelWithString: L("配置 AI 增强生成", "Configure AI enhanced generation"))
        title.font = .systemFont(ofSize: 27, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.07, alpha: 1)
        stack.addArrangedSubview(title)

        let copy = NSTextField(wrappingLabelWithString: L(
            "默认推荐 API易：地址和模型已经填好，通常只需要填写 API Key。下一步接入生成器后，导入工作台会优先调用模型，失败再回退本地生成。",
            "APIYI is the recommended default: endpoint and model are prefilled, so you usually only need an API key. Once the generator is wired in, the import studio will call the model first and fall back locally on failure."
        ))
        copy.font = .systemFont(ofSize: 13)
        copy.textColor = NSColor(calibratedRed: 0.39, green: 0.30, blue: 0.22, alpha: 1)
        copy.widthAnchor.constraint(equalToConstant: 620).isActive = true
        stack.addArrangedSubview(copy)
        return stack
    }

    private func settingsCard() -> NSView {
        let card = NSStackView()
        card.orientation = .vertical
        card.spacing = 13
        card.alignment = .leading
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.91, alpha: 1).cgColor
        card.layer?.cornerRadius = 24
        card.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        card.widthAnchor.constraint(equalToConstant: 660).isActive = true

        enabledButton.title = L("启用 AI 增强生成", "Enable AI enhanced generation")
        enabledButton.target = self
        enabledButton.action = #selector(toggleEnabled)
        card.addArrangedSubview(enabledButton)

        providerPopup.addItems(withTitles: AIProvider.allCases.map(\.title))
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        card.addArrangedSubview(labeledControl(L("供应商", "Provider"), providerPopup))

        qualityPopup.addItems(withTitles: AIQualityMode.allCases.map(\.title))
        card.addArrangedSubview(labeledControl(L("质量模式", "Quality mode"), qualityPopup))

        modelField.placeholderString = L("模型名称，例如 gpt-image-2-all", "Model name, e.g. gpt-image-2-all")
        modelField.widthAnchor.constraint(equalToConstant: 600).isActive = true
        card.addArrangedSubview(labeledControl(L("模型", "Model"), modelField))

        endpointField.placeholderString = L("API Endpoint URL", "API endpoint URL")
        endpointField.widthAnchor.constraint(equalToConstant: 600).isActive = true
        card.addArrangedSubview(labeledControl("Endpoint", endpointField))

        apiKeyField.placeholderString = L("API Key 会保存到 macOS Keychain", "API key is stored in macOS Keychain")
        apiKeyField.widthAnchor.constraint(equalToConstant: 600).isActive = true
        card.addArrangedSubview(labeledControl("API Key", apiKeyField))

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.25, alpha: 1)
        card.addArrangedSubview(statusLabel)

        return card
    }

    private func footerView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let note = NSTextField(wrappingLabelWithString: L(
            "测试连接按钮目前只检查必填项，不会发起网络请求。真实 API 调用会在下一步生成器里接入。",
            "Test connection currently validates required fields only and does not make a network request. Real API calls will be wired into the generator next."
        ))
        note.font = .systemFont(ofSize: 12)
        note.textColor = NSColor(calibratedRed: 0.43, green: 0.33, blue: 0.25, alpha: 1)
        note.widthAnchor.constraint(equalToConstant: 420).isActive = true
        row.addArrangedSubview(note)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let test = NSButton(title: L("测试配置", "Test Config"), target: self, action: #selector(testConfig))
        test.bezelStyle = .rounded
        test.controlSize = .large
        row.addArrangedSubview(test)

        let save = NSButton(title: L("保存", "Save"), target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        save.controlSize = .large
        save.widthAnchor.constraint(equalToConstant: 96).isActive = true
        row.addArrangedSubview(save)

        return row
    }

    private func labeledControl(_ title: String, _ control: NSView) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 5
        stack.alignment = .leading

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.17, alpha: 1)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(control)
        return stack
    }

    private func loadSettings() {
        let settings = store.load()
        enabledButton.state = settings.isEnabled ? .on : .off
        providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: settings.provider) ?? 0)
        qualityPopup.selectItem(at: AIQualityMode.allCases.firstIndex(of: settings.qualityMode) ?? 0)
        modelField.stringValue = settings.model
        endpointField.stringValue = settings.endpoint
        apiKeyField.stringValue = store.loadAPIKey()
        statusLabel.stringValue = settings.isEnabled
            ? L("AI 增强已启用。", "AI enhancement is enabled.")
            : L("AI 增强未启用，当前仍使用本地兜底生成。", "AI enhancement is disabled; local fallback is still used.")
    }

    @objc private func providerChanged() {
        let provider = selectedProvider()
        modelField.stringValue = provider.defaultModel
        endpointField.stringValue = provider.defaultEndpoint
    }

    @objc private func toggleEnabled() {
        statusLabel.stringValue = enabledButton.state == .on
            ? L("启用后，接入生成器时会优先使用模型。", "When enabled, the generator will prefer model output once wired in.")
            : L("关闭后，将使用本地兜底生成。", "When disabled, local fallback generation is used.")
    }

    @objc private func testConfig() {
        let missingKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingModel = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingEndpoint = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if enabledButton.state == .on && (missingKey || missingModel || missingEndpoint) {
            statusLabel.stringValue = L("配置不完整：启用 AI 时需要 API Key、模型和 Endpoint。", "Incomplete config: API key, model, and endpoint are required when AI is enabled.")
            statusLabel.textColor = .systemRed
            return
        }

        statusLabel.stringValue = L("配置格式可用。当前未发起网络测试。", "Config format looks valid. No network test was performed.")
        statusLabel.textColor = NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.23, alpha: 1)
    }

    @objc private func saveSettings() {
        let settings = AIModelSettings(
            isEnabled: enabledButton.state == .on,
            provider: selectedProvider(),
            model: modelField.stringValue,
            endpoint: endpointField.stringValue,
            qualityMode: selectedQualityMode()
        )
        store.save(settings)
        store.saveAPIKey(apiKeyField.stringValue)
        statusLabel.stringValue = L("已保存模型配置。", "Model settings saved.")
        statusLabel.textColor = NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.23, alpha: 1)
    }

    private func selectedProvider() -> AIProvider {
        let index = providerPopup.indexOfSelectedItem
        return AIProvider.allCases.indices.contains(index) ? AIProvider.allCases[index] : .fal
    }

    private func selectedQualityMode() -> AIQualityMode {
        let index = qualityPopup.indexOfSelectedItem
        return AIQualityMode.allCases.indices.contains(index) ? AIQualityMode.allCases[index] : .cheap
    }
}
