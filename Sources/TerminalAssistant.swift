import AppKit
import ApplicationServices
import Darwin

struct TerminalAssistantSettings {
    var isEnabled: Bool
    var allowOneClickEnter: Bool
    var allowAutoConfirmLowRisk: Bool

    static let defaults = TerminalAssistantSettings(
        isEnabled: false,
        allowOneClickEnter: true,
        allowAutoConfirmLowRisk: false
    )
}

final class TerminalAssistantSettingsStore {
    static let shared = TerminalAssistantSettingsStore()

    private enum Key {
        static let enabled = "terminalAssistant.enabled"
        static let oneClick = "terminalAssistant.oneClickEnter"
        static let autoLowRisk = "terminalAssistant.autoLowRisk"
    }

    func load() -> TerminalAssistantSettings {
        let defaults = UserDefaults.standard
        let hasOneClickValue = defaults.object(forKey: Key.oneClick) != nil
        return TerminalAssistantSettings(
            isEnabled: defaults.bool(forKey: Key.enabled),
            allowOneClickEnter: hasOneClickValue ? defaults.bool(forKey: Key.oneClick) : TerminalAssistantSettings.defaults.allowOneClickEnter,
            allowAutoConfirmLowRisk: defaults.bool(forKey: Key.autoLowRisk)
        )
    }

    func save(_ settings: TerminalAssistantSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.isEnabled, forKey: Key.enabled)
        defaults.set(settings.allowOneClickEnter, forKey: Key.oneClick)
        defaults.set(settings.allowAutoConfirmLowRisk, forKey: Key.autoLowRisk)
    }
}

enum TerminalCLIKind {
    case codex
    case claude

    var commandName: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        }
    }

    var sessionTitle: String {
        switch self {
        case .codex: return "SkillsPet Codex"
        case .claude: return "SkillsPet Claude"
        }
    }
}

enum TerminalAssistantController {
    private struct TTYTarget {
        let path: String
        let input: String
    }

    struct AgentProcess {
        let pid: pid_t
        let ttyName: String
        let cliKind: TerminalCLIKind

        var ttyPath: String { "/dev/\(ttyName)" }
    }

    struct SessionNotice {
        enum State {
            case finished
            case failed(Int)
        }

        let id: String
        let cliName: String
        let state: State
    }

    private static var lastAutoConfirmAt = Date.distantPast
    private static let autoConfirmCooldown: TimeInterval = 12
    private static var knownAgentPIDs: [pid_t: AgentProcess] = [:]
    private(set) static var lastDiscoveredAgents: [AgentProcess] = []

    // We cannot reliably inspect arbitrary terminal contents yet, so this list only gates where
    // a manual Codex/Claude approval Enter may be sent.
    static let terminalBundleIDs = Set([
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
        "co.zeit.hyper",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92"
    ])

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func frontmostTerminalAppName() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              terminalBundleIDs.contains(bundleID) else {
            return nil
        }
        return app.localizedName ?? bundleID
    }

    static func frontmostTerminalBundleID() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              terminalBundleIDs.contains(bundleID) else {
            return nil
        }
        return bundleID
    }

    static func discoverAgentProcesses() -> [AgentProcess] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,tty,comm"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            debugLog("ps launch failed: \(error.localizedDescription)")
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var results: [AgentProcess] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3 else { continue }
            let tty = String(parts[1])
            guard tty != "??" else { continue }
            guard let pid = pid_t(parts[0]) else { continue }
            let comm = String(parts[2])
            let baseName = (comm as NSString).lastPathComponent.lowercased()
            let kind: TerminalCLIKind
            if baseName.contains("codex") {
                kind = .codex
            } else if baseName.contains("claude") {
                kind = .claude
            } else {
                continue
            }
            results.append(AgentProcess(pid: pid, ttyName: tty, cliKind: kind))
        }
        lastDiscoveredAgents = results
        return results
    }

    static func processBasedSessionNotices(currentProcesses: [AgentProcess]) -> [SessionNotice] {
        let currentPIDs = Set(currentProcesses.map(\.pid))
        var notices: [SessionNotice] = []
        for (pid, agent) in knownAgentPIDs {
            if !currentPIDs.contains(pid) {
                notices.append(SessionNotice(
                    id: "proc-\(pid)",
                    cliName: agent.cliKind.commandName,
                    state: .finished
                ))
            }
        }
        knownAgentPIDs = knownAgentPIDs.filter { currentPIDs.contains($0.key) }
        for agent in currentProcesses where knownAgentPIDs[agent.pid] == nil {
            knownAgentPIDs[agent.pid] = agent
        }
        return notices
    }

    static func launchCLI(_ cli: TerminalCLIKind) -> Bool {
        runAppleScript(launchTerminalScript(for: cli))
    }

    static func completedSessionNotices() -> [SessionNotice] {
        let directory = sessionStatusDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return files.compactMap { url in
            guard url.pathExtension == "status",
                  let content = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }

            let parts = content.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "|", omittingEmptySubsequences: false)
                .map(String.init)
            guard parts.count >= 2 else { return nil }

            let status = parts[0]
            let cliName = parts[1]
            let id = url.deletingPathExtension().lastPathComponent

            if status == "done" {
                return SessionNotice(id: id, cliName: cliName, state: .finished)
            }

            if status == "failed" {
                let code = parts.count >= 3 ? (Int(parts[2]) ?? 1) : 1
                return SessionNotice(id: id, cliName: cliName, state: .failed(code))
            }

            return nil
        }
    }

    static func sendReturnToFrontmostTerminal() -> Bool {
        if sendReturnUsingTTY() {
            return true
        }

        if sendReturnUsingTerminalAutomation() {
            return true
        }

        guard hasAccessibilityPermission(),
              frontmostTerminalAppName() != nil else {
            return false
        }

        let keyCodeReturn: CGKeyCode = 36
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeReturn, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeReturn, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return true
    }

    static func autoConfirmIfNeeded(agents: [AgentProcess] = []) -> Bool {
        let settings = TerminalAssistantSettingsStore.shared.load()
        guard settings.isEnabled, settings.allowAutoConfirmLowRisk else {
            return false
        }

        let now = Date()
        guard now.timeIntervalSince(lastAutoConfirmAt) >= autoConfirmCooldown else {
            return false
        }

        guard !agents.isEmpty else { return false }

        for agent in agents {
            if autoConfirmForProcess(agent) {
                lastAutoConfirmAt = now
                debugLog("auto-confirm succeeded for \(agent.cliKind.commandName) pid=\(agent.pid) tty=\(agent.ttyPath)")
                return true
            }
        }

        return false
    }

    private static func sendReturnUsingTTY() -> Bool {
        guard let target = matchingTTYTarget() else {
            debugLog("terminal tty match failed")
            return false
        }
        return injectInputToTTY(path: target.path, input: target.input)
    }

    private static func injectInputToTTY(path: String, input: String) -> Bool {
        let normalizedPath = path.hasPrefix("/dev/") ? path : "/dev/\(path)"
        let fd = open(normalizedPath, O_WRONLY | O_NOCTTY)
        guard fd >= 0 else {
            debugLog("terminal tty open failed: \(normalizedPath) errno=\(errno)")
            return false
        }
        defer { close(fd) }

        for byte in input.utf8 {
            var inputByte = byte
            let result = ioctl(fd, TIOCSTI, &inputByte)
            if result == -1 {
                debugLog("terminal tty input injection failed: \(normalizedPath) errno=\(errno)")
                return false
            }
        }

        debugLog("terminal tty input injected: \(normalizedPath) input=\(debugInputName(input))")
        return true
    }

    private static func matchingTTYTarget() -> TTYTarget? {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if runningBundleIDs.contains("com.apple.Terminal"),
           let raw = runAppleScriptForString(terminalTTYScript()),
           let target = parseTTYTarget(raw) {
            return target
        }

        if runningBundleIDs.contains("com.googlecode.iterm2"),
           let raw = runAppleScriptForString(iTermTTYScript()),
           let target = parseTTYTarget(raw) {
            return target
        }

        return nil
    }

    private static func parseTTYTarget(_ raw: String) -> TTYTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "|", maxSplits: 1).map(String.init)
        let path = parts[0]
        let action = parts.count > 1 ? parts[1] : "enter"
        let input = action == "yes-menu" ? "1\n" : "\n"
        return TTYTarget(path: path, input: input)
    }

    private static func debugInputName(_ value: String) -> String {
        value == "1\n" ? "1-newline" : "newline"
    }

    private static func sendReturnUsingTerminalAutomation() -> Bool {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if runningBundleIDs.contains("com.apple.Terminal"),
           runAppleScript(terminalScript()) {
            return true
        }

        if runningBundleIDs.contains("com.googlecode.iterm2"),
           runAppleScript(iTermScript()) {
            return true
        }

        return false
    }

    private static func runAppleScriptForString(_ script: String) -> String? {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        let output = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            debugLog("terminal tty lookup failed: \(errorInfo)")
            return nil
        }
        let value = output.stringValue ?? ""
        debugLog("terminal tty lookup result: \(value)")
        return value
    }

    private static func runAppleScript(_ script: String) -> Bool {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        let output = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            debugLog("terminal automation failed: \(errorInfo)")
            return false
        }
        let success = output.stringValue == "ok"
        debugLog("terminal automation result: \(output.stringValue ?? "nil")")
        return success
    }

    private static func launchTerminalScript(for cli: TerminalCLIKind) -> String {
        let sessionID = "\(cli.commandName)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        let statusURL = sessionStatusDirectory().appendingPathComponent("\(sessionID).status")
        try? FileManager.default.createDirectory(at: statusURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let title = shellSingleQuoted(cli.sessionTitle)
        let cliName = shellSingleQuoted(cli.commandName)
        let statusPath = shellSingleQuoted(statusURL.path)
        let command = "status_file=\(statusPath); cli_name=\(cliName); printf 'running|%s\\n' \"$cli_name\" > \"$status_file\"; printf '\\033]0;%s\\007' \(title); \(cli.commandName); exit_code=$?; if [ $exit_code -eq 0 ]; then printf 'done|%s|0\\n' \"$cli_name\" > \"$status_file\"; printf '\\n[SkillsPet] %s 已完成。\\n' \"$cli_name\"; else printf 'failed|%s|%s\\n' \"$cli_name\" \"$exit_code\" > \"$status_file\"; printf '\\n[SkillsPet] %s 退出，状态码：%s。\\n' \"$cli_name\" \"$exit_code\"; fi"
        let commandLiteral = appleScriptStringLiteral(command)
        return """
        tell application id "com.apple.Terminal"
            activate
            do script \(commandLiteral)
            return "ok"
        end tell
        """
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func sessionStatusDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillsPetLite", isDirectory: true)
            .appendingPathComponent("terminal-sessions", isDirectory: true)
    }

    private static func autoConfirmForProcess(_ agent: AgentProcess) -> Bool {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        if runningBundleIDs.contains("com.apple.Terminal"),
           let action = autoConfirmTerminalTabAction(ttyPath: agent.ttyPath) {
            let input = action == "yes-menu" ? "1\n" : "\n"
            if injectInputToTTY(path: agent.ttyPath, input: input) { return true }
            debugLog("TIOCSTI blocked, falling back to AppleScript for Terminal.app tty=\(agent.ttyPath)")
            return sendInputToTerminalTab(ttyPath: agent.ttyPath, action: action)
        }

        if runningBundleIDs.contains("com.googlecode.iterm2"),
           let action = autoConfirmITermSessionAction(ttyPath: agent.ttyPath) {
            let input = action == "yes-menu" ? "1\n" : "\n"
            if injectInputToTTY(path: agent.ttyPath, input: input) { return true }
            debugLog("TIOCSTI blocked, falling back to AppleScript for iTerm2 tty=\(agent.ttyPath)")
            return sendInputToITermSession(ttyPath: agent.ttyPath, action: action)
        }

        return false
    }

    private static func sendInputToTerminalTab(ttyPath: String, action: String) -> Bool {
        let ttyLiteral = appleScriptStringLiteral(ttyPath)
        let textToSend = action == "yes-menu" ? "1" : ""
        let textLiteral = appleScriptStringLiteral(textToSend)
        let script = """
        tell application id "com.apple.Terminal"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        if (tty of terminalTab) as text is equal to \(ttyLiteral) then
                            set selected of terminalTab to true
                            set index of terminalWindow to 1
                            do script \(textLiteral) in terminalTab
                            return "ok"
                        end if
                    end repeat
                end repeat
            end if
        end tell
        return "no-match"
        """
        return runAppleScript(script)
    }

    private static func sendInputToITermSession(ttyPath: String, action: String) -> Bool {
        let ttyLiteral = appleScriptStringLiteral(ttyPath)
        let textToSend = action == "yes-menu" ? "1" : ""
        let textLiteral = appleScriptStringLiteral(textToSend)
        let script = """
        tell application id "com.googlecode.iterm2"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        repeat with terminalSession in sessions of terminalTab
                            if (tty of terminalSession) as text is equal to \(ttyLiteral) then
                                tell terminalSession to write text \(textLiteral)
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
        end tell
        return "no-match"
        """
        return runAppleScript(script)
    }

    private static func autoConfirmTerminalTabAction(ttyPath: String) -> String? {
        let ttyLiteral = appleScriptStringLiteral(ttyPath)
        let script = """
        tell application id "com.apple.Terminal"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        if (tty of terminalTab) as text is equal to \(ttyLiteral) then
                            set tabContents to ""
                            try
                                set tabContents to (history of terminalTab) as text
                            end try
                            if my looksYesMenu(tabContents) then return "yes-menu"
                            if my looksWaiting(tabContents) then return "enter"
                            return ""
                        end if
                    end repeat
                end repeat
            end if
        end tell
        return ""

        on looksYesMenu(valueText)
            if valueText contains "Do you want to proceed?" then return true
            if valueText contains "❯ 1. Yes" then return true
            if valueText contains "1. Yes" and valueText contains "3. No" then return true
            return false
        end looksYesMenu

        on looksWaiting(valueText)
            if valueText contains "press enter" then return true
            if valueText contains "Press Enter" then return true
            if valueText contains "continue?" then return true
            if valueText contains "Continue?" then return true
            if valueText contains "do you want to" then return true
            if valueText contains "Do you want to" then return true
            if valueText contains "approve" then return true
            if valueText contains "Approve" then return true
            if valueText contains "allow" then return true
            if valueText contains "Allow" then return true
            if valueText contains "confirm" then return true
            if valueText contains "Confirm" then return true
            if valueText contains "proceed" then return true
            if valueText contains "Proceed" then return true
            if valueText contains "y/n" then return true
            if valueText contains "[y/n]" then return true
            if valueText contains "是否" then return true
            if valueText contains "确认" then return true
            if valueText contains "继续" then return true
            if valueText contains "允许" then return true
            return false
        end looksWaiting
        """
        guard let result = runAppleScriptForString(script), !result.isEmpty else { return nil }
        return result
    }

    private static func autoConfirmITermSessionAction(ttyPath: String) -> String? {
        let ttyLiteral = appleScriptStringLiteral(ttyPath)
        let script = """
        tell application id "com.googlecode.iterm2"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        repeat with terminalSession in sessions of terminalTab
                            if (tty of terminalSession) as text is equal to \(ttyLiteral) then
                                set sessionContents to ""
                                try
                                    set sessionContents to (contents of terminalSession) as text
                                end try
                                set sessionName to ""
                                try
                                    set sessionName to (name of terminalSession) as text
                                end try
                                set probe to sessionName & linefeed & sessionContents
                                if my looksYesMenu(probe) then return "yes-menu"
                                if my looksWaiting(probe) then return "enter"
                                return ""
                            end if
                        end repeat
                    end repeat
                end repeat
            end if
        end tell
        return ""

        on looksYesMenu(valueText)
            if valueText contains "Do you want to proceed?" then return true
            if valueText contains "❯ 1. Yes" then return true
            if valueText contains "1. Yes" and valueText contains "3. No" then return true
            return false
        end looksYesMenu

        on looksWaiting(valueText)
            if valueText contains "press enter" then return true
            if valueText contains "Press Enter" then return true
            if valueText contains "continue?" then return true
            if valueText contains "Continue?" then return true
            if valueText contains "do you want to" then return true
            if valueText contains "Do you want to" then return true
            if valueText contains "approve" then return true
            if valueText contains "Approve" then return true
            if valueText contains "allow" then return true
            if valueText contains "Allow" then return true
            if valueText contains "confirm" then return true
            if valueText contains "Confirm" then return true
            if valueText contains "proceed" then return true
            if valueText contains "Proceed" then return true
            if valueText contains "y/n" then return true
            if valueText contains "[y/n]" then return true
            if valueText contains "是否" then return true
            if valueText contains "确认" then return true
            if valueText contains "继续" then return true
            if valueText contains "允许" then return true
            return false
        end looksWaiting
        """
        guard let result = runAppleScriptForString(script), !result.isEmpty else { return nil }
        return result
    }

    private static func autoConfirmScript() -> String {
        """
        set didConfirm to false
        set scannedCount to 0
        set maxContentLength to 0
        set sawYes to false
        set sawProceed to false
        if application id "com.apple.Terminal" is running then
            tell application id "com.apple.Terminal"
                if (count of windows) is greater than 0 then
                    repeat with terminalWindow in windows
                        repeat with terminalTab in tabs of terminalWindow
                            set tabContents to ""
                            try
                                set tabContents to (history of terminalTab) as text
                            end try
                            set scannedCount to scannedCount + 1
                            set contentLength to length of tabContents
                            if contentLength > maxContentLength then set maxContentLength to contentLength
                            if tabContents contains "Yes" then set sawYes to true
                            if tabContents contains "yes" then set sawYes to true
                            if tabContents contains "proceed" then set sawProceed to true
                            if tabContents contains "Proceed" then set sawProceed to true
                            if my looksYesMenu(tabContents) then
                                set selected of terminalTab to true
                                set index of terminalWindow to 1
                                activate
                                delay 0.15
                                tell application "System Events"
                                    keystroke "1"
                                    key code 36
                                end tell
                                set didConfirm to true
                                exit repeat
                            end if
                        end repeat
                        if didConfirm then exit repeat
                    end repeat
                end if
            end tell
        end if
        if didConfirm then return "ok"

        if application id "com.googlecode.iterm2" is running then
            tell application id "com.googlecode.iterm2"
                if (count of windows) is greater than 0 then
                    repeat with terminalWindow in windows
                        repeat with terminalTab in tabs of terminalWindow
                            repeat with terminalSession in sessions of terminalTab
                                set sessionName to ""
                                set sessionContents to ""
                                try
                                    set sessionName to (name of terminalSession) as text
                                end try
                            try
                                set sessionContents to (contents of terminalSession) as text
                            end try
                            set probe to sessionName & linefeed & sessionContents
                            set scannedCount to scannedCount + 1
                            set contentLength to length of probe
                            if contentLength > maxContentLength then set maxContentLength to contentLength
                            if probe contains "Yes" then set sawYes to true
                            if probe contains "yes" then set sawYes to true
                            if probe contains "proceed" then set sawProceed to true
                            if probe contains "Proceed" then set sawProceed to true
                            if my looksYesMenu(probe) then
                                select terminalWindow
                                select terminalTab
                                    select terminalSession
                                    activate
                                    delay 0.15
                                    tell application "System Events"
                                        keystroke "1"
                                        key code 36
                                    end tell
                                    set didConfirm to true
                                    exit repeat
                                end if
                            end repeat
                            if didConfirm then exit repeat
                        end repeat
                        if didConfirm then exit repeat
                    end repeat
                end if
            end tell
        end if
        if didConfirm then return "ok"
        return "no-match scanned=" & scannedCount & " maxLen=" & maxContentLength & " sawYes=" & sawYes & " sawProceed=" & sawProceed

        on matchesAgent(valueText)
            if valueText contains "claude" then return true
            if valueText contains "Claude" then return true
            if valueText contains "CLAUDE" then return true
            if valueText contains "codex" then return true
            if valueText contains "Codex" then return true
            if valueText contains "CODEX" then return true
            return false
        end matchesAgent

        on looksYesMenu(valueText)
            if valueText contains "Do you want to proceed?" then return true
            if valueText contains "❯ 1. Yes" then return true
            if valueText contains "1. Yes" and valueText contains "3. No" then return true
            return false
        end looksYesMenu
        """
    }

    private static func terminalScript() -> String {
        """
        tell application id "com.apple.Terminal"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        set tabContents to ""
                        try
                            set tabContents to (history of terminalTab) as text
                        end try
                        set probe to tabContents
                        if my matchesAgent(probe) and my looksWaiting(probe) then
                            set selected of terminalTab to true
                            set frontmost to true
                            do script "" in terminalTab
                            return "ok"
                        end if
                    end repeat
                end repeat
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        set tabContents to ""
                        try
                            set tabContents to (history of terminalTab) as text
                        end try
                        set probe to tabContents
                        if my matchesAgent(probe) then
                            set selected of terminalTab to true
                            set frontmost to true
                            do script "" in terminalTab
                            return "ok"
                        end if
                    end repeat
                end repeat
                do script "" in selected tab of front window
                return "ok"
            end if
        end tell
        return "no-window"

        on matchesAgent(valueText)
            if valueText contains "claude" then return true
            if valueText contains "Claude" then return true
            if valueText contains "CLAUDE" then return true
            if valueText contains "codex" then return true
            if valueText contains "Codex" then return true
            if valueText contains "CODEX" then return true
            return false
        end matchesAgent

        on looksWaiting(valueText)
            if valueText contains "press enter" then return true
            if valueText contains "Press Enter" then return true
            if valueText contains "continue?" then return true
            if valueText contains "Continue?" then return true
            if valueText contains "do you want to" then return true
            if valueText contains "Do you want to" then return true
            if valueText contains "approve" then return true
            if valueText contains "Approve" then return true
            if valueText contains "allow" then return true
            if valueText contains "Allow" then return true
            if valueText contains "confirm" then return true
            if valueText contains "Confirm" then return true
            if valueText contains "proceed" then return true
            if valueText contains "Proceed" then return true
            if valueText contains "y/n" then return true
            if valueText contains "[y/n]" then return true
            if valueText contains "是否" then return true
            if valueText contains "确认" then return true
            if valueText contains "继续" then return true
            if valueText contains "允许" then return true
            return false
        end looksWaiting
        """
    }

    private static func terminalTTYScript() -> String {
        """
        tell application id "com.apple.Terminal"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        set tabContents to ""
                        try
                            set tabContents to (history of terminalTab) as text
                        end try
                        set probe to tabContents
                        if my looksYesMenu(probe) then
                            return ((tty of terminalTab) as text) & "|yes-menu"
                        end if
                        if my matchesAgent(probe) and my looksWaiting(probe) then
                            return ((tty of terminalTab) as text) & "|enter"
                        end if
                    end repeat
                end repeat
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        set tabContents to ""
                        try
                            set tabContents to (history of terminalTab) as text
                        end try
                        set probe to tabContents
                        if my matchesAgent(probe) then
                            return ((tty of terminalTab) as text) & "|enter"
                        end if
                    end repeat
                end repeat
                return ((tty of selected tab of front window) as text) & "|enter"
            end if
        end tell
        return ""

        on matchesAgent(valueText)
            if valueText contains "claude" then return true
            if valueText contains "Claude" then return true
            if valueText contains "CLAUDE" then return true
            if valueText contains "codex" then return true
            if valueText contains "Codex" then return true
            if valueText contains "CODEX" then return true
            return false
        end matchesAgent

        on looksWaiting(valueText)
            if valueText contains "press enter" then return true
            if valueText contains "Press Enter" then return true
            if valueText contains "continue?" then return true
            if valueText contains "Continue?" then return true
            if valueText contains "do you want to" then return true
            if valueText contains "Do you want to" then return true
            if valueText contains "approve" then return true
            if valueText contains "Approve" then return true
            if valueText contains "allow" then return true
            if valueText contains "Allow" then return true
            if valueText contains "confirm" then return true
            if valueText contains "Confirm" then return true
            if valueText contains "proceed" then return true
            if valueText contains "Proceed" then return true
            if valueText contains "y/n" then return true
            if valueText contains "[y/n]" then return true
            if valueText contains "是否" then return true
            if valueText contains "确认" then return true
            if valueText contains "继续" then return true
            if valueText contains "允许" then return true
            return false
        end looksWaiting

        on looksYesMenu(valueText)
            if valueText contains "Do you want to proceed?" then return true
            if valueText contains "❯ 1. Yes" then return true
            if valueText contains "1. Yes" and valueText contains "3. No" then return true
            return false
        end looksYesMenu
        """
    }

    private static func iTermScript() -> String {
        """
        tell application id "com.googlecode.iterm2"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        repeat with terminalSession in sessions of terminalTab
                            set sessionName to ""
                            set sessionContents to ""
                            try
                                set sessionName to (name of terminalSession) as text
                            end try
                            try
                                set sessionContents to (contents of terminalSession) as text
                            end try
                            set probe to sessionName & linefeed & sessionContents
                            if my matchesAgent(probe) and my looksWaiting(probe) then
                                tell terminalSession to write text ""
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        repeat with terminalSession in sessions of terminalTab
                            set sessionName to ""
                            set sessionContents to ""
                            try
                                set sessionName to (name of terminalSession) as text
                            end try
                            try
                                set sessionContents to (contents of terminalSession) as text
                            end try
                            set probe to sessionName & linefeed & sessionContents
                            if my matchesAgent(probe) then
                                tell terminalSession to write text ""
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
                tell current session of current window
                    write text ""
                end tell
                return "ok"
            end if
        end tell
        return "no-window"

        on matchesAgent(valueText)
            if valueText contains "claude" then return true
            if valueText contains "Claude" then return true
            if valueText contains "CLAUDE" then return true
            if valueText contains "codex" then return true
            if valueText contains "Codex" then return true
            if valueText contains "CODEX" then return true
            return false
        end matchesAgent

        on looksWaiting(valueText)
            if valueText contains "press enter" then return true
            if valueText contains "Press Enter" then return true
            if valueText contains "continue?" then return true
            if valueText contains "Continue?" then return true
            if valueText contains "do you want to" then return true
            if valueText contains "Do you want to" then return true
            if valueText contains "approve" then return true
            if valueText contains "Approve" then return true
            if valueText contains "allow" then return true
            if valueText contains "Allow" then return true
            if valueText contains "confirm" then return true
            if valueText contains "Confirm" then return true
            if valueText contains "proceed" then return true
            if valueText contains "Proceed" then return true
            if valueText contains "y/n" then return true
            if valueText contains "[y/n]" then return true
            if valueText contains "是否" then return true
            if valueText contains "确认" then return true
            if valueText contains "继续" then return true
            if valueText contains "允许" then return true
            return false
        end looksWaiting
        """
    }

    private static func iTermTTYScript() -> String {
        """
        tell application id "com.googlecode.iterm2"
            if (count of windows) is greater than 0 then
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        repeat with terminalSession in sessions of terminalTab
                            set sessionName to ""
                            set sessionContents to ""
                            try
                                set sessionName to (name of terminalSession) as text
                            end try
                            try
                                set sessionContents to (contents of terminalSession) as text
                            end try
                            set probe to sessionName & linefeed & sessionContents
                            if my looksYesMenu(probe) then
                                return ((tty of terminalSession) as text) & "|yes-menu"
                            end if
                            if my matchesAgent(probe) and my looksWaiting(probe) then
                                return ((tty of terminalSession) as text) & "|enter"
                            end if
                        end repeat
                    end repeat
                end repeat
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                        repeat with terminalSession in sessions of terminalTab
                            set sessionName to ""
                            set sessionContents to ""
                            try
                                set sessionName to (name of terminalSession) as text
                            end try
                            try
                                set sessionContents to (contents of terminalSession) as text
                            end try
                            set probe to sessionName & linefeed & sessionContents
                            if my matchesAgent(probe) then
                                return ((tty of terminalSession) as text) & "|enter"
                            end if
                        end repeat
                    end repeat
                end repeat
                return ((tty of current session of current window) as text) & "|enter"
            end if
        end tell
        return ""

        on matchesAgent(valueText)
            if valueText contains "claude" then return true
            if valueText contains "Claude" then return true
            if valueText contains "CLAUDE" then return true
            if valueText contains "codex" then return true
            if valueText contains "Codex" then return true
            if valueText contains "CODEX" then return true
            return false
        end matchesAgent

        on looksWaiting(valueText)
            if valueText contains "press enter" then return true
            if valueText contains "Press Enter" then return true
            if valueText contains "continue?" then return true
            if valueText contains "Continue?" then return true
            if valueText contains "do you want to" then return true
            if valueText contains "Do you want to" then return true
            if valueText contains "approve" then return true
            if valueText contains "Approve" then return true
            if valueText contains "allow" then return true
            if valueText contains "Allow" then return true
            if valueText contains "confirm" then return true
            if valueText contains "Confirm" then return true
            if valueText contains "proceed" then return true
            if valueText contains "Proceed" then return true
            if valueText contains "y/n" then return true
            if valueText contains "[y/n]" then return true
            if valueText contains "是否" then return true
            if valueText contains "确认" then return true
            if valueText contains "继续" then return true
            if valueText contains "允许" then return true
            return false
        end looksWaiting

        on looksYesMenu(valueText)
            if valueText contains "Do you want to proceed?" then return true
            if valueText contains "❯ 1. Yes" then return true
            if valueText contains "1. Yes" and valueText contains "3. No" then return true
            return false
        end looksYesMenu
        """
    }
}

extension Notification.Name {
    static let openTerminalAssistantSettings = Notification.Name("openTerminalAssistantSettings")
    static let approveFrontmostTerminalPrompt = Notification.Name("approveFrontmostTerminalPrompt")
    static let launchCodexCLI = Notification.Name("launchCodexCLI")
    static let launchClaudeCLI = Notification.Name("launchClaudeCLI")
    static let terminalAssistantSessionNotice = Notification.Name("terminalAssistantSessionNotice")
}
