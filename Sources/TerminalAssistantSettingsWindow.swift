import AppKit

final class TerminalAssistantSettingsWindowController: NSWindowController {
    private let store = TerminalAssistantSettingsStore.shared

    private let enabledButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let oneClickButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoConfirmButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let permissionStatus = NSTextField(labelWithString: "")
    private let frontAppStatus = NSTextField(labelWithString: "")
    private let discoveryStatus = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("终端确认助手", "Terminal Approval Assistant")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.82, alpha: 1)

        super.init(window: window)
        window.contentView = buildContentView()
        window.center()
        loadSettings()
        refreshStatus()
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
        stack.addArrangedSubview(actionsRow())
        stack.addArrangedSubview(footerView())
        return root
    }

    private func headerView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading

        let eyebrow = NSTextField(labelWithString: L("安全确认", "SAFE APPROVAL"))
        eyebrow.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.16, alpha: 1)
        stack.addArrangedSubview(eyebrow)

        let title = NSTextField(labelWithString: L("让桌宠辅助 Codex / Claude CLI 确认", "Let the pet assist Codex / Claude CLI approvals"))
        title.font = .systemFont(ofSize: 25, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.07, alpha: 1)
        stack.addArrangedSubview(title)

        let copy = NSTextField(wrappingLabelWithString: L(
            "第一版只支持 Codex CLI / Claude CLI 的人工辅助确认。Apple Terminal / iTerm 会优先走自动化权限发送 Enter；其它终端才回退辅助功能权限。不会做无条件自动确认。",
            "The first version only supports assisted Codex CLI / Claude CLI approvals. Apple Terminal / iTerm use Automation permission first; other terminals fall back to Accessibility. It will not perform unconditional auto-approval."
        ))
        copy.font = .systemFont(ofSize: 13)
        copy.textColor = NSColor(calibratedRed: 0.39, green: 0.30, blue: 0.22, alpha: 1)
        copy.widthAnchor.constraint(equalToConstant: 630).isActive = true
        stack.addArrangedSubview(copy)

        return stack
    }

    private func settingsCard() -> NSView {
        let card = NSStackView()
        card.orientation = .vertical
        card.spacing = 14
        card.alignment = .leading
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.91, alpha: 1).cgColor
        card.layer?.cornerRadius = 24
        card.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        card.widthAnchor.constraint(equalToConstant: 660).isActive = true

        enabledButton.title = L("启用 Codex / Claude CLI 确认助手", "Enable Codex / Claude CLI Approval Assistant")
        card.addArrangedSubview(enabledButton)

        oneClickButton.title = L("允许菜单一键向前台 Codex / Claude 终端发送 Enter", "Allow menu one-click Return to frontmost Codex / Claude terminal")
        card.addArrangedSubview(oneClickButton)

        autoConfirmButton.title = L("自动确认低风险 Codex/Claude 提示（仅 Terminal.app/iTerm2）", "Auto-approve low-risk Codex/Claude prompts (Terminal.app / iTerm2 only)")
        card.addArrangedSubview(autoConfirmButton)

        discoveryStatus.font = .systemFont(ofSize: 12)
        discoveryStatus.textColor = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.25, alpha: 1)
        card.addArrangedSubview(discoveryStatus)

        permissionStatus.font = .systemFont(ofSize: 12)
        permissionStatus.textColor = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.25, alpha: 1)
        card.addArrangedSubview(permissionStatus)

        frontAppStatus.font = .systemFont(ofSize: 12)
        frontAppStatus.textColor = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.25, alpha: 1)
        card.addArrangedSubview(frontAppStatus)

        return card
    }

    private func actionsRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        let label = NSTextField(labelWithString: L("快捷操作", "Quick Actions"))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.25, alpha: 1)
        row.addArrangedSubview(label)

        let launchCodex = NSButton(title: L("启动 Codex", "Launch Codex"), target: self, action: #selector(launchCodex))
        launchCodex.bezelStyle = .rounded
        launchCodex.controlSize = .regular
        row.addArrangedSubview(launchCodex)

        let launchClaude = NSButton(title: L("启动 Claude", "Launch Claude"), target: self, action: #selector(launchClaude))
        launchClaude.bezelStyle = .rounded
        launchClaude.controlSize = .regular
        row.addArrangedSubview(launchClaude)

        let approve = NSButton(title: L("手动确认当前提示", "Approve Current Prompt"), target: self, action: #selector(manualApprove))
        approve.bezelStyle = .rounded
        approve.controlSize = .regular
        row.addArrangedSubview(approve)

        return row
    }

    private func footerView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let warning = NSTextField(wrappingLabelWithString: L(
            "不要把它当作无条件自动回车工具。删除、重置、sudo、联网安装等高风险提示必须人工判断。",
            "Do not treat this as an unconditional auto-Return tool. Deletion, reset, sudo, network install, and other high-risk prompts must stay human-reviewed."
        ))
        warning.font = .systemFont(ofSize: 12)
        warning.textColor = NSColor(calibratedRed: 0.55, green: 0.25, blue: 0.18, alpha: 1)
        warning.widthAnchor.constraint(equalToConstant: 380).isActive = true
        row.addArrangedSubview(warning)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let requestPermission = NSButton(title: L("申请权限", "Request Permission"), target: self, action: #selector(requestPermission))
        requestPermission.bezelStyle = .rounded
        requestPermission.controlSize = .large
        row.addArrangedSubview(requestPermission)

        let save = NSButton(title: L("保存", "Save"), target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        save.controlSize = .large
        save.widthAnchor.constraint(equalToConstant: 92).isActive = true
        row.addArrangedSubview(save)

        return row
    }

    private func loadSettings() {
        let settings = store.load()
        enabledButton.state = settings.isEnabled ? .on : .off
        oneClickButton.state = settings.allowOneClickEnter ? .on : .off
        autoConfirmButton.state = settings.allowAutoConfirmLowRisk ? .on : .off
    }

    private func refreshStatus() {
        permissionStatus.stringValue = TerminalAssistantController.hasAccessibilityPermission()
            ? L("辅助功能权限：已授权", "Accessibility permission: granted")
            : L("辅助功能权限：未授权。Apple Terminal / iTerm 可先尝试自动化权限；其它终端需要辅助功能权限。", "Accessibility permission: not granted. Apple Terminal / iTerm can try Automation first; other terminals require Accessibility.")

        if let appName = TerminalAssistantController.frontmostTerminalAppName() {
            frontAppStatus.stringValue = L("当前前台终端：\(appName)", "Current frontmost terminal: \(appName)")
        } else {
            frontAppStatus.stringValue = L("当前前台不是终端类 App。请把正在运行 Codex / Claude CLI 的终端放到前台。", "The frontmost app is not terminal-like. Bring the terminal running Codex / Claude CLI to the front.")
        }

        let agents = TerminalAssistantController.lastDiscoveredAgents
        if agents.isEmpty {
            discoveryStatus.stringValue = L("未发现运行中的 Claude/Codex 会话", "No running Claude/Codex sessions found")
        } else {
            let names = agents.map { "\($0.cliKind.commandName) (\($0.ttyName))" }.joined(separator: ", ")
            discoveryStatus.stringValue = L("发现 \(agents.count) 个会话：\(names)", "Found \(agents.count) session(s): \(names)")
        }
    }

    @objc private func launchCodex() {
        NotificationCenter.default.post(name: .launchCodexCLI, object: nil)
    }

    @objc private func launchClaude() {
        NotificationCenter.default.post(name: .launchClaudeCLI, object: nil)
    }

    @objc private func manualApprove() {
        NotificationCenter.default.post(name: .approveFrontmostTerminalPrompt, object: nil)
    }

    @objc private func requestPermission() {
        TerminalAssistantController.requestAccessibilityPermission()
        refreshStatus()
    }

    @objc private func saveSettings() {
        store.save(TerminalAssistantSettings(
            isEnabled: enabledButton.state == .on,
            allowOneClickEnter: oneClickButton.state == .on,
            allowAutoConfirmLowRisk: autoConfirmButton.state == .on
        ))
        refreshStatus()
        window?.close()
    }
}
