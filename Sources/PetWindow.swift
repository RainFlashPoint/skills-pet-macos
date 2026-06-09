import AppKit

final class PetWindow: NSPanel, NSWindowDelegate {
    private enum Constants {
        static let width: CGFloat = 430
        static let height: CGFloat = 232
        static let positionKey = "petWindowOrigin"
    }

    private let external: ExternalPaths

    init(external: ExternalPaths) {
        self.external = external
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

        contentView = PetView(frame: NSRect(origin: .zero, size: frame.size), external: external)
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

    @discardableResult
    func reviveIfNeeded(forceCenter: Bool) -> Bool {
        let shouldRevive = !isVisible || alphaValue < 0.05 || isMiniaturized || !isOnVisibleScreen()
        guard shouldRevive || forceCenter else { return false }
        debugLog("reviveIfNeeded visible=\(isVisible) alpha=\(alphaValue) mini=\(isMiniaturized)")
        if forceCenter || !isOnVisibleScreen() {
            moveToVisibleCenter()
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
        moveToVisibleCenter()
    }

    private func isOnVisibleScreen() -> Bool {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        return visibleFrames.contains { $0.intersects(frame) }
    }

    private func savePosition() {
        let origin = frame.origin
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Constants.positionKey)
    }
}
