import AppKit

enum PetBehaviorMode: String, CaseIterable {
    case roaming
    case docked

    var title: String {
        switch self {
        case .roaming: return "自由乱动"
        case .docked: return "右下角停靠"
        }
    }
}

final class PetWindow: NSPanel, NSWindowDelegate {
    private enum Constants {
        static let width: CGFloat = 430
        static let height: CGFloat = 232
        static let behaviorModeKey = "petBehaviorMode"
        static let roamingPositionKey = "petWindowOrigin.roaming"
        static let dockedPositionKey = "petWindowOrigin.docked"
        static let dockMargin: CGFloat = 16
    }

    private let external: ExternalPaths
    private(set) var behaviorMode: PetBehaviorMode

    init(external: ExternalPaths) {
        self.external = external
        self.behaviorMode = PetWindow.loadBehaviorMode()
        debugLog("PetWindow init start")

        let frame = NSRect(x: 80, y: 520, width: Constants.width, height: Constants.height)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = "SkillsPetLite"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        delegate = self

        contentView = PetView(frame: NSRect(origin: .zero, size: frame.size), external: external, behaviorMode: behaviorMode)
        restorePositionIfNeeded()
        debugLog("PetWindow init done")
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func moveToVisibleCenter() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let x = screen.midX - frame.width / 2
        let y = screen.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
        savePosition()
    }

    func moveToDockedCorner() {
        guard let screen = currentVisibleFrame() else { return }
        let x = screen.maxX - frame.width - Constants.dockMargin
        let y = screen.minY + Constants.dockMargin
        setFrameOrigin(NSPoint(x: x, y: y))
        savePosition()
    }

    func setBehaviorMode(_ mode: PetBehaviorMode) {
        guard behaviorMode != mode else { return }
        behaviorMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Constants.behaviorModeKey)
        (contentView as? PetView)?.applyBehaviorMode(mode)

        switch mode {
        case .roaming:
            restoreRoamingPositionIfNeeded()
        case .docked:
            moveToDockedCorner()
        }
    }

    @discardableResult
    func reviveIfNeeded(forceCenter: Bool) -> Bool {
        let shouldRevive = !isVisible || alphaValue < 0.05 || isMiniaturized || !isOnVisibleScreen()
        guard shouldRevive || forceCenter else { return false }
        debugLog("reviveIfNeeded visible=\(isVisible) alpha=\(alphaValue) mini=\(isMiniaturized)")
        switch behaviorMode {
        case .roaming:
            if forceCenter || !isOnVisibleScreen() {
                moveToVisibleCenter()
            }
        case .docked:
            moveToDockedCorner()
        }
        alphaValue = 1
        orderFrontRegardless()
        return true
    }

    func windowDidMove(_ notification: Notification) {
        savePosition()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        debugLog("windowShouldClose intercepted")
        orderFrontRegardless()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        debugLog("windowWillClose")
        orderFrontRegardless()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        debugLog("windowDidMiniaturize")
        orderFrontRegardless()
    }

    func windowDidResignMain(_ notification: Notification) {
        if !isVisible {
            debugLog("windowDidResignMain while hidden")
            orderFrontRegardless()
        }
    }

    private func restorePositionIfNeeded() {
        switch behaviorMode {
        case .roaming:
            restoreRoamingPositionIfNeeded()
        case .docked:
            moveToDockedCorner()
        }
    }

    private func isOnVisibleScreen() -> Bool {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        return visibleFrames.contains { $0.intersects(frame) }
    }

    private func savePosition() {
        let origin = frame.origin
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: positionKey(for: behaviorMode))
    }

    private func restoreRoamingPositionIfNeeded() {
        if let origin = storedOrigin(for: Constants.roamingPositionKey),
           isOriginVisible(origin) {
            setFrameOrigin(origin)
            return
        }
        moveToVisibleCenter()
    }

    private func storedOrigin(for key: String) -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = raw.split(separator: ",").map(String.init)
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]) else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    private func isOriginVisible(_ origin: NSPoint) -> Bool {
        let candidate = NSRect(origin: origin, size: frame.size)
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        return visibleFrames.contains { $0.intersects(candidate) }
    }

    private func positionKey(for mode: PetBehaviorMode) -> String {
        switch mode {
        case .roaming:
            return Constants.roamingPositionKey
        case .docked:
            return Constants.dockedPositionKey
        }
    }

    private func currentVisibleFrame() -> NSRect? {
        screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    private static func loadBehaviorMode() -> PetBehaviorMode {
        let raw = UserDefaults.standard.string(forKey: Constants.behaviorModeKey)
        return raw.flatMap(PetBehaviorMode.init(rawValue:)) ?? .roaming
    }
}
