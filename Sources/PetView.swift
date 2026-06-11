import AppKit

final class PetView: NSView {
    private enum Pose: CaseIterable {
        case recline
        case loaf
        case sit
        case play
        case beg
        case stretch
        case walk
        case sleep

        var menuTitle: String {
            switch self {
            case .recline: return "Recline"
            case .loaf: return "Loaf"
            case .sit: return "Sit"
            case .play: return "Play"
            case .beg: return "Beg"
            case .stretch: return "Stretch"
            case .walk: return "Walk"
            case .sleep: return "Sleep"
            }
        }
    }

    private struct PoseDefinition {
        let frames: [NSImage]
        let frameDuration: TimeInterval
        let stateDuration: TimeInterval
    }

    private struct EyeSpec {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private enum Constants {
        static let tickInterval: TimeInterval = 1.0 / 30.0
        static let walkSpeed: CGFloat = 1.45
        static let dragMargin: CGFloat = 12
        static let dragFollow: CGFloat = 0.34
        static let dragReleaseDecay: CGFloat = 0.82
    }

    private let external: ExternalPaths
    private static let preferredPoseOrder: [Pose] = [.recline, .play, .beg, .walk, .sit, .loaf, .stretch, .walk, .sleep, .sit]

    private var behaviorMode: PetBehaviorMode
    private let poses: [Pose: PoseDefinition]
    private let poseOrder: [Pose]

    private var currentPoseIndex = 0
    private var currentFrameIndex = 0
    private var poseElapsed: TimeInterval = 0
    private var frameElapsed: TimeInterval = 0
    private var motionPhase: CGFloat = 0
    private var dockMotionPhase: CGFloat = 0
    private var walkDirection: CGFloat = -1
    private var dragOrigin: NSPoint?
    private var windowOrigin: NSPoint?
    private var dragTargetOrigin: NSPoint?
    private var dragReleaseVelocity: CGPoint = .zero
    private var dragVisualProgress: CGFloat = 0
    private var displayTimer: Timer?
    private var lookTarget: CGFloat = 0
    private var lookOffset: CGFloat = 0
    private var nextLookChange: TimeInterval = 1.2
    private var blinkAmount: CGFloat = 0
    private var blinkTimer: TimeInterval = 2.4
    private var blinkingForward = false
    private var tailTargetAngle: CGFloat = 0
    private var tailAngle: CGFloat = 0
    private var nextTailFlick: TimeInterval = 3.0
    private var tailReturning = false
    private var earAngle: CGFloat = 0
    private var earTargetAngle: CGFloat = 0
    private var nextEarTwitch: TimeInterval = 4.2
    private var earReturning = false
    private var walkIntroPause: TimeInterval = 0
    private var edgePause: TimeInterval = 0
    private var stretchProgress: CGFloat = 0
    private var clickReaction: CGFloat = 0
    private var previousPose: Pose = .recline
    private var begReach: CGFloat = 0
    private var edgeRestPending = false

    init(frame frameRect: NSRect, external: ExternalPaths, behaviorMode: PetBehaviorMode) {
        self.external = external
        self.behaviorMode = behaviorMode
        let builtPoses = PetView.buildPoses(external: external)
        self.poses = builtPoses
        self.poseOrder = PetView.buildPoseOrder(from: builtPoses)
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let timer = Timer.scheduledTimer(withTimeInterval: Constants.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.current?.imageInterpolation = .high
        guard let frameImage = currentFrame() else {
            drawFallback(in: bounds)
            return
        }

        let drawState = transformState(for: currentPose)
        let maxWidth = bounds.width - 20
        let maxHeight = bounds.height - 32
        let scale = min(maxWidth / frameImage.size.width, maxHeight / frameImage.size.height) * drawState.scale
        let drawSize = NSSize(width: frameImage.size.width * scale, height: frameImage.size.height * scale)
        let dockOffset = dockedMotionOffset(for: currentPose)
        let baseRect = NSRect(
            x: (bounds.width - drawSize.width) / 2 + lookOffset + earTwitchOffset().x + dockOffset.x,
            y: (bounds.height - drawSize.height) / 2 + drawState.verticalOffset + earTwitchOffset().y + dockOffset.y,
            width: drawSize.width,
            height: drawSize.height
        )

        drawShadow(width: drawSize.width, y: max(8, baseRect.minY - 8), alpha: drawState.shadowAlpha)
        drawSprite(frameImage, in: baseRect, mirrored: walkDirection > 0 && currentPose == .walk, pose: currentPose)
        drawBlink(in: baseRect, pose: currentPose)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            external.openHub()
            return
        }

        triggerClickReaction(at: event.locationInWindow)
        guard behaviorMode == .roaming else { return }
        dragOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
        dragTargetOrigin = window?.frame.origin
        dragReleaseVelocity = .zero
    }

    override func mouseUp(with event: NSEvent) {
        guard behaviorMode == .roaming else { return }
        dragOrigin = nil
        windowOrigin = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard behaviorMode == .roaming else { return }
        guard let dragOrigin, let windowOrigin, let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragOrigin.x
        let dy = current.y - dragOrigin.y
        let target = NSPoint(x: windowOrigin.x + dx, y: windowOrigin.y + dy)
        let clamped = clampedOrigin(for: target, window: window)
        if let existing = dragTargetOrigin {
            dragReleaseVelocity = CGPoint(x: clamped.x - existing.x, y: clamped.y - existing.y)
        }
        dragTargetOrigin = clamped
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: L("打开技能中心", "Open Skills Hub"), action: #selector(openHub), keyEquivalent: "")
        menu.addItem(withTitle: L("打开技能目录", "Open Catalog"), action: #selector(openCatalog), keyEquivalent: "")
        menu.addItem(modeMenuItem())
        menu.addItem(withTitle: L("切换姿态", "Switch Pose"), action: #selector(switchPose), keyEquivalent: "")
        menu.addItem(withTitle: L("开始走路", "Start Walk"), action: #selector(startWalk), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("退出", "Quit"), action: #selector(quitApp), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openHub() {
        external.openHub()
    }

    @objc private func openCatalog() {
        external.openCatalog()
    }

    @objc private func setRoamingMode() {
        setBehaviorMode(.roaming)
    }

    @objc private func setDockedMode() {
        setBehaviorMode(.docked)
    }

    @objc private func switchPose() {
        advancePose()
    }

    @objc private func startWalk() {
        setPose(.walk)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private var currentPose: Pose {
        poseOrder[safe: currentPoseIndex] ?? .recline
    }

    private func tick() {
        motionPhase += 0.09
        dockMotionPhase += 0.07
        poseElapsed += Constants.tickInterval
        frameElapsed += Constants.tickInterval
        updateDragVisual()
        updateDragMotion()
        updateLook()
        updateBlink()
        updateTail()
        updateEarTwitch()
        updateStretch()
        updateClickReaction()
        updateBegReach()

        if let definition = poses[currentPose], definition.frames.count > 1, frameElapsed >= definition.frameDuration {
            frameElapsed = 0
            currentFrameIndex = (currentFrameIndex + 1) % definition.frames.count
        }

        if behaviorMode == .roaming, currentPose == .walk {
            moveWalkIfNeeded()
            if edgeRestPending, edgePause <= 0 {
                edgeRestPending = false
                setPose(edgeRestPose())
            }
        }

        if let definition = poses[currentPose], poseElapsed >= definition.stateDuration {
            advancePose()
        }

        needsDisplay = true
    }

    private func advancePose() {
        guard !poseOrder.isEmpty else { return }
        previousPose = currentPose
        let nextPose = suggestedNextPose(after: currentPose, mode: behaviorMode)
        currentPoseIndex = poseOrder.firstIndex(of: nextPose) ?? ((currentPoseIndex + 1) % poseOrder.count)
        resetPoseTiming()
    }

    private func setPose(_ pose: Pose) {
        guard !poseOrder.isEmpty else { return }
        guard let index = poseOrder.firstIndex(of: pose) else { return }
        previousPose = currentPose
        currentPoseIndex = index
        resetPoseTiming()
    }

    private func resetPoseTiming() {
        poseElapsed = 0
        frameElapsed = 0
        currentFrameIndex = 0
        lookTarget = 0
        if currentPose == .walk {
            walkIntroPause = 0.75
            edgeRestPending = false
        }
        if previousPose == .sleep && (currentPose == .sit || currentPose == .stretch) {
            stretchProgress = 1
        }
    }

    private func currentFrame() -> NSImage? {
        if let frame = poses[currentPose]?.frames[safe: currentFrameIndex] {
            return frame
        }
        if let fallback = poses[currentPose]?.frames.first {
            debugLog("frame fallback for pose \(currentPose.menuTitle) at index \(currentFrameIndex)")
            return fallback
        }
        if let fallbackPose = poseOrder.first(where: { poses[$0]?.frames.isEmpty == false }),
           let image = poses[fallbackPose]?.frames.first {
            debugLog("pose fallback from \(currentPose.menuTitle) to \(fallbackPose.menuTitle)")
            return image
        }
        debugLog("no sprite available for current pose \(currentPose.menuTitle)")
        return nil
    }

    private func moveWalkIfNeeded() {
        guard behaviorMode == .roaming else { return }
        guard dragOrigin == nil, let window = window else { return }
        if walkIntroPause > 0 {
            walkIntroPause -= Constants.tickInterval
            lookTarget = walkDirection < 0 ? -10 : 10
            return
        }
        if edgePause > 0 {
            edgePause -= Constants.tickInterval
            lookTarget = walkDirection < 0 ? 10 : -10
            return
        }
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var origin = window.frame.origin
        origin.x += Constants.walkSpeed * walkDirection

        let minX = screen.minX
        let maxX = screen.maxX - window.frame.width

        if origin.x <= minX {
            origin.x = minX
            walkDirection = 1
            edgePause = 0.9
            edgeRestPending = true
            triggerClickReaction()
        } else if origin.x >= maxX {
            origin.x = maxX
            walkDirection = -1
            edgePause = 0.9
            edgeRestPending = true
            triggerClickReaction()
        }

        let stepBob = abs(sin(motionPhase * 1.8)) * 2.2
        let centeredY = screen.minY + 40
        origin.y = centeredY + stepBob
        window.setFrameOrigin(origin)
    }

    private func clampedOrigin(for target: NSPoint, window: NSWindow) -> NSPoint {
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let minX = screen.minX + Constants.dragMargin
        let maxX = screen.maxX - window.frame.width - Constants.dragMargin
        let minY = screen.minY + Constants.dragMargin
        let maxY = screen.maxY - window.frame.height - Constants.dragMargin
        return NSPoint(
            x: min(max(target.x, minX), maxX),
            y: min(max(target.y, minY), maxY)
        )
    }

    private func updateDragVisual() {
        let target: CGFloat = dragOrigin == nil ? 0 : 1
        dragVisualProgress += (target - dragVisualProgress) * 0.24
        if behaviorMode == .docked {
            dragVisualProgress *= 0.92
        }
    }

    private func updateDragMotion() {
        guard behaviorMode == .roaming else {
            dragTargetOrigin = nil
            dragReleaseVelocity = .zero
            return
        }
        guard let window = window else { return }

        if let dragTargetOrigin {
            let current = window.frame.origin
            let next = NSPoint(
                x: current.x + (dragTargetOrigin.x - current.x) * Constants.dragFollow,
                y: current.y + (dragTargetOrigin.y - current.y) * Constants.dragFollow
            )
            window.setFrameOrigin(clampedOrigin(for: next, window: window))
            if dragOrigin == nil, hypot(dragTargetOrigin.x - next.x, dragTargetOrigin.y - next.y) < 0.8 {
                self.dragTargetOrigin = nil
            }
            return
        }

        guard dragOrigin == nil, (abs(dragReleaseVelocity.x) > 0.2 || abs(dragReleaseVelocity.y) > 0.2) else { return }
        let current = window.frame.origin
        let target = NSPoint(x: current.x + dragReleaseVelocity.x * 0.28, y: current.y + dragReleaseVelocity.y * 0.28)
        let clamped = clampedOrigin(for: target, window: window)
        window.setFrameOrigin(clamped)
        if clamped != target {
            dragReleaseVelocity.x *= -0.18
            dragReleaseVelocity.y *= -0.18
        } else {
            dragReleaseVelocity.x *= Constants.dragReleaseDecay
            dragReleaseVelocity.y *= Constants.dragReleaseDecay
        }
    }

    private func updateStretch() {
        if stretchProgress > 0 {
            stretchProgress = max(0, stretchProgress - 0.05)
        }
    }

    private func updateBegReach() {
        let target: CGFloat = currentPose == .beg ? 1 : 0
        begReach += (target - begReach) * 0.14
    }

    private func updateClickReaction() {
        if clickReaction > 0 {
            clickReaction = max(0, clickReaction - 0.08)
        }
    }

    private func triggerClickReaction(at point: NSPoint? = nil) {
        clickReaction = 1
        tailTargetAngle = 0.16
        tailReturning = false
        earTargetAngle = -0.16
        earReturning = false
        if let point {
            lookTarget = point.x < bounds.midX ? -12 : 12
        } else {
            lookTarget = walkDirection < 0 ? -10 : 10
        }
        if behaviorMode == .docked {
            if currentPose == .sleep {
                setPose(.stretch)
            } else if currentPose != .walk, poseElapsed > 1.0 {
                setPose(.walk)
            }
        } else if currentPose != .walk, currentPose != .sleep, poseElapsed > 1.0,
                  [.recline, .loaf, .sit].contains(currentPose) {
            setPose(.play)
        }
    }

    private func suggestedNextPose(after pose: Pose, mode: PetBehaviorMode) -> Pose {
        switch mode {
        case .docked:
            return dockedNextPose(after: pose)
        case .roaming:
            return roamingNextPose(after: pose)
        }
    }

    private func roamingNextPose(after pose: Pose) -> Pose {
        switch activityBand() {
        case .night:
            switch pose {
            case .sleep: return .loaf
            case .walk, .play, .beg: return .sleep
            case .stretch: return .sit
            default: return Bool.random() ? .sleep : .loaf
            }
        case .evening:
            if pose == .walk { return Bool.random() ? .sit : .loaf }
            if pose == .sleep { return .stretch }
            if pose == .play || pose == .beg { return .sit }
            return [.walk, .loaf, .sit, .recline, .stretch].randomElement() ?? .sit
        case .day:
            if pose == .sleep { return .stretch }
            if pose == .walk { return Bool.random() ? .sit : .loaf }
            if pose == .recline || pose == .loaf { return Bool.random() ? .walk : .play }
            return [.walk, .play, .beg, .sit, .loaf, .stretch].randomElement() ?? .walk
        }
    }

    private func dockedNextPose(after pose: Pose) -> Pose {
        switch pose {
        case .sleep: return .stretch
        case .walk: return Bool.random() ? .sit : .loaf
        case .play: return .walk
        case .beg: return .walk
        case .stretch: return Bool.random() ? .walk : .sit
        case .recline: return .walk
        case .sit: return Bool.random() ? .walk : .loaf
        case .loaf: return Bool.random() ? .walk : .recline
        }
    }

    private func edgeRestPose() -> Pose {
        switch activityBand() {
        case .night:
            return .sleep
        case .evening:
            return Bool.random() ? .loaf : .sit
        case .day:
            return [.sit, .loaf, .recline].randomElement() ?? .sit
        }
    }

    private func modeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("模式", "Mode"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L("模式", "Mode"))
        submenu.addItem(modeMenuEntry(title: PetBehaviorMode.roaming.title, action: #selector(setRoamingMode), isSelected: behaviorMode == .roaming))
        submenu.addItem(modeMenuEntry(title: PetBehaviorMode.docked.title, action: #selector(setDockedMode), isSelected: behaviorMode == .docked))
        item.submenu = submenu
        return item
    }

    private func modeMenuEntry(title: String, action: Selector, isSelected: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isSelected ? .on : .off
        return item
    }

    private func setBehaviorMode(_ mode: PetBehaviorMode) {
        guard behaviorMode != mode else { return }
        behaviorMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "petBehaviorMode")
        (window as? PetWindow)?.setBehaviorMode(mode)

        if mode == .roaming {
            dragVisualProgress = 0
            edgeRestPending = false
        } else {
            dragOrigin = nil
            windowOrigin = nil
            dragTargetOrigin = nil
            dragReleaseVelocity = .zero
        }
        needsDisplay = true
    }

    func applyBehaviorMode(_ mode: PetBehaviorMode) {
        guard behaviorMode != mode else { return }
        behaviorMode = mode
        if mode == .docked {
            dragOrigin = nil
            windowOrigin = nil
            dragTargetOrigin = nil
            dragReleaseVelocity = .zero
        }
        needsDisplay = true
    }

    private enum ActivityBand {
        case day
        case evening
        case night
    }

    private func activityBand() -> ActivityBand {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 22...23, 0...6:
            return .night
        case 18...21:
            return .evening
        default:
            return .day
        }
    }

    private func transformState(for pose: Pose) -> (scale: CGFloat, verticalOffset: CGFloat, shadowAlpha: CGFloat) {
        let dragScale = 1 - dragVisualProgress * 0.05
        let dragLift = dragVisualProgress * 10
        let dragShadowBoost = dragVisualProgress * 0.04
        let clickScale = 1 + clickReaction * 0.035
        let clickLift = clickReaction * 4
        let stretchScale = 1 + stretchProgress * 0.08
        let stretchLift = stretchProgress * 6
        let begScale = 1 + begReach * 0.08
        let begLift = begReach * 8

        switch pose {
        case .recline:
            return (
                scale: (1 + sin(motionPhase) * 0.015) * dragScale * clickScale,
                verticalOffset: sin(motionPhase) * 3.5 + dragLift + clickLift,
                shadowAlpha: 0.18 + dragShadowBoost
            )
        case .loaf:
            return (
                scale: (1 + sin(motionPhase * 0.85) * 0.012) * dragScale * clickScale,
                verticalOffset: sin(motionPhase * 0.85) * 2.5 + dragLift + clickLift,
                shadowAlpha: 0.16 + dragShadowBoost
            )
        case .walk:
            return (
                scale: (1 + sin(motionPhase * 1.8) * 0.012) * dragScale * clickScale,
                verticalOffset: abs(sin(motionPhase * 1.8)) * 3.6 + dragLift + clickLift,
                shadowAlpha: 0.22 + dragShadowBoost
            )
        case .sit:
            return (
                scale: (1 + sin(motionPhase * 0.7) * 0.014) * dragScale * clickScale * stretchScale,
                verticalOffset: sin(motionPhase * 0.7) * 2.2 + dragLift + clickLift + stretchLift,
                shadowAlpha: 0.17 + dragShadowBoost
            )
        case .play:
            return (
                scale: (1.03 + abs(sin(motionPhase * 1.6)) * 0.05) * dragScale * clickScale,
                verticalOffset: abs(sin(motionPhase * 1.6)) * 10 + dragLift + clickLift + 8,
                shadowAlpha: 0.2 + dragShadowBoost
            )
        case .beg:
            return (
                scale: (1 + abs(sin(motionPhase * 1.9)) * 0.03) * dragScale * clickScale * begScale,
                verticalOffset: abs(sin(motionPhase * 1.9)) * 4 + dragLift + clickLift + begLift + 2,
                shadowAlpha: 0.21 + dragShadowBoost
            )
        case .stretch:
            return (
                scale: (1.08 + abs(sin(motionPhase * 0.9)) * 0.03) * dragScale * clickScale * stretchScale,
                verticalOffset: sin(motionPhase * 0.9) * 1.2 + dragLift + clickLift + 4 + stretchLift,
                shadowAlpha: 0.15 + dragShadowBoost
            )
        case .sleep:
            return (
                scale: (1 + sin(motionPhase * 0.45) * 0.02) * dragScale,
                verticalOffset: sin(motionPhase * 0.45) * 1.5 + dragLift,
                shadowAlpha: 0.14 + dragShadowBoost
            )
        }
    }

    private func dockedMotionOffset(for pose: Pose) -> CGPoint {
        guard behaviorMode == .docked else { return .zero }

        let breath = sin(dockMotionPhase * 0.8) * 1.8
        let sway = sin(dockMotionPhase * 1.3) * 2.8
        let tap = abs(sin(dockMotionPhase * 2.1)) * 1.4
        let clickNudge = clickReaction * 4

        switch pose {
        case .walk:
            return CGPoint(x: sway * 1.6 + clickNudge * 0.2, y: tap + breath * 0.8)
        case .play:
            return CGPoint(x: sway * 0.8, y: tap * 1.4 + breath * 1.6 + clickNudge * 0.2)
        case .beg:
            return CGPoint(x: sway * 0.5, y: tap * 1.0 + breath * 2.0 + clickNudge * 0.15)
        case .stretch:
            return CGPoint(x: sway * 0.6, y: breath * 2.4 + tap)
        case .sleep:
            return CGPoint(x: sway * 0.15, y: breath * 0.45)
        case .recline:
            return CGPoint(x: sway * 0.45, y: breath * 1.2)
        case .sit:
            return CGPoint(x: sway * 0.7, y: breath * 1.4 + tap * 0.8)
        case .loaf:
            return CGPoint(x: sway * 0.4, y: breath * 1.0)
        }
    }

    private func drawShadow(width: CGFloat, y: CGFloat, alpha: CGFloat) {
        let shadowWidth = max(96, width * 0.62)
        let shadowRect = NSRect(x: (bounds.width - shadowWidth) / 2, y: y, width: shadowWidth, height: 14)
        let path = NSBezierPath(ovalIn: shadowRect)
        NSColor(calibratedWhite: 0.08, alpha: alpha).setFill()
        path.fill()
    }

    private func drawSprite(_ image: NSImage, in rect: NSRect, mirrored: Bool, pose: Pose) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.draw(in: rect)
            return
        }

        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: rect.midX + tailFlickOffset().x, y: rect.midY + tailFlickOffset().y)
        if mirrored {
            context.scaleBy(x: -1, y: 1)
        }
        context.rotate(by: poseRotation(for: pose) + tailAngle * 0.18)
        let drawRect = poseAdjustedRect(for: pose, base: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
        image.draw(in: drawRect)
        context.restoreGState()
    }

    private func poseRotation(for pose: Pose) -> CGFloat {
        switch pose {
        case .play:
            return CGFloat(sin(motionPhase * 1.7)) * 0.07
        case .beg:
            return CGFloat(sin(motionPhase * 1.9)) * 0.04
        case .walk:
            return CGFloat(sin(motionPhase * 1.8)) * 0.022
        case .stretch:
            return -0.04
        default:
            return 0
        }
    }

    private func poseAdjustedRect(for pose: Pose, base: CGRect) -> CGRect {
        switch pose {
        case .play:
            return base.offsetBy(dx: 0, dy: 12)
        case .beg:
            return CGRect(x: base.minX - 4, y: base.minY + 10, width: base.width * 0.96, height: base.height * 1.08)
        case .stretch:
            return CGRect(x: base.minX - 6, y: base.minY + 4, width: base.width * 1.08, height: base.height * 0.94)
        default:
            return base
        }
    }

    private func drawBlink(in rect: NSRect, pose: Pose) {
        guard blinkAmount > 0.02, currentPose != .walk else { return }
        let eyes = eyeSpecs(for: pose, in: rect)
        let furColor = NSColor(calibratedWhite: 0.93, alpha: 0.98)

        furColor.setFill()
        for eye in eyes {
            let openHeight = eye.height
            let lidHeight = max(2, openHeight * blinkAmount)
            let lidRect = NSRect(x: eye.x, y: eye.y + (openHeight - lidHeight) * 0.52, width: eye.width, height: lidHeight)
            let path = NSBezierPath(roundedRect: lidRect, xRadius: lidHeight / 2, yRadius: lidHeight / 2)
            path.fill()
        }
    }

    private func updateLook() {
        guard currentPose != .walk, currentPose != .sleep else {
            lookTarget = 0
            lookOffset += (0 - lookOffset) * 0.08
            return
        }

        nextLookChange -= Constants.tickInterval
        if nextLookChange <= 0 {
            let options: [CGFloat]
            switch currentPose {
            case .play:
                options = [-16, -10, 0, 10, 16]
            case .beg:
                options = [-8, 0, 8]
            default:
                options = [-10, -5, 0, 5, 10]
            }
            lookTarget = options.randomElement() ?? 0
            nextLookChange = currentPose == .beg ? Double.random(in: 1.4 ... 2.6) : Double.random(in: 2.4 ... 4.8)
        }

        lookOffset += (lookTarget - lookOffset) * 0.08
    }

    private func updateBlink() {
        blinkTimer -= Constants.tickInterval
        if blinkTimer <= 0, blinkAmount == 0 {
            blinkingForward = true
            blinkTimer = Double.random(in: 2.8 ... 5.6)
        }

        if blinkingForward {
            blinkAmount += 0.28
            if blinkAmount >= 1 {
                blinkAmount = 1
                blinkingForward = false
            }
        } else if blinkAmount > 0 {
            blinkAmount = max(0, blinkAmount - 0.34)
        }
    }

    private func updateTail() {
        guard currentPose != .sleep else {
            tailAngle += (0 - tailAngle) * 0.08
            return
        }

        nextTailFlick -= Constants.tickInterval
        if nextTailFlick <= 0, tailTargetAngle == 0 {
            tailTargetAngle = currentPose == .walk ? 0.06 : 0.12
            tailReturning = false
            nextTailFlick = Double.random(in: 3.2 ... 6.2)
        }

        if tailTargetAngle != 0 && !tailReturning {
            tailAngle += (tailTargetAngle - tailAngle) * 0.18
            if abs(tailAngle - tailTargetAngle) < 0.015 {
                tailTargetAngle = -tailTargetAngle * 0.55
                tailReturning = true
            }
        } else {
            tailAngle += (tailTargetAngle - tailAngle) * 0.16
            if tailReturning, abs(tailAngle - tailTargetAngle) < 0.018 {
                tailTargetAngle = 0
            }
            if tailReturning, abs(tailAngle) < 0.01, tailTargetAngle == 0 {
                tailAngle = 0
                tailReturning = false
            }
        }
    }

    private func updateEarTwitch() {
        guard currentPose != .sleep, currentPose != .walk else {
            earAngle += (0 - earAngle) * 0.18
            return
        }

        nextEarTwitch -= Constants.tickInterval
        if nextEarTwitch <= 0, earTargetAngle == 0 {
            earTargetAngle = -0.13
            earReturning = false
            nextEarTwitch = Double.random(in: 4.6 ... 8.4)
        }

        if earTargetAngle != 0 && !earReturning {
            earAngle += (earTargetAngle - earAngle) * 0.34
            if abs(earAngle - earTargetAngle) < 0.02 {
                earTargetAngle = 0.08
                earReturning = true
            }
        } else {
            earAngle += (earTargetAngle - earAngle) * 0.3
            if earReturning, abs(earAngle - earTargetAngle) < 0.02 {
                earTargetAngle = 0
            }
            if earReturning, abs(earAngle) < 0.01, earTargetAngle == 0 {
                earAngle = 0
                earReturning = false
            }
        }
    }

    private func earTwitchOffset() -> CGPoint {
        guard currentPose != .walk, currentPose != .sleep else { return .zero }
        return CGPoint(x: earAngle * 16, y: abs(earAngle) * 6 + clickReaction * 2)
    }

    private func tailFlickOffset() -> CGPoint {
        guard currentPose != .sleep else { return .zero }
        return CGPoint(x: abs(tailAngle) * 8, y: tailAngle * 6)
    }

    private func eyeSpecs(for pose: Pose, in rect: NSRect) -> [EyeSpec] {
        switch pose {
        case .recline:
            return [
                EyeSpec(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.60, width: rect.width * 0.05, height: rect.height * 0.035),
                EyeSpec(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.585, width: rect.width * 0.045, height: rect.height * 0.03)
            ]
        case .loaf:
            return [
                EyeSpec(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.59, width: rect.width * 0.05, height: rect.height * 0.032),
                EyeSpec(x: rect.minX + rect.width * 0.275, y: rect.minY + rect.height * 0.58, width: rect.width * 0.045, height: rect.height * 0.028)
            ]
        case .sit:
            return [
                EyeSpec(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.71, width: rect.width * 0.055, height: rect.height * 0.032),
                EyeSpec(x: rect.minX + rect.width * 0.245, y: rect.minY + rect.height * 0.695, width: rect.width * 0.048, height: rect.height * 0.026)
            ]
        case .play:
            return [
                EyeSpec(x: rect.minX + rect.width * 0.19, y: rect.minY + rect.height * 0.72, width: rect.width * 0.055, height: rect.height * 0.03),
                EyeSpec(x: rect.minX + rect.width * 0.255, y: rect.minY + rect.height * 0.705, width: rect.width * 0.048, height: rect.height * 0.024)
            ]
        case .beg:
            return [
                EyeSpec(x: rect.minX + rect.width * 0.21, y: rect.minY + rect.height * 0.77, width: rect.width * 0.05, height: rect.height * 0.028),
                EyeSpec(x: rect.minX + rect.width * 0.275, y: rect.minY + rect.height * 0.755, width: rect.width * 0.044, height: rect.height * 0.022)
            ]
        case .stretch:
            return [
                EyeSpec(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.62, width: rect.width * 0.05, height: rect.height * 0.022),
                EyeSpec(x: rect.minX + rect.width * 0.23, y: rect.minY + rect.height * 0.605, width: rect.width * 0.043, height: rect.height * 0.018)
            ]
        case .sleep:
            return [
                EyeSpec(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.50, width: rect.width * 0.06, height: rect.height * 0.016)
            ]
        case .walk:
            return []
        }
    }

    private func drawFallback(in rect: NSRect) {
        let bubble = NSBezierPath(roundedRect: rect.insetBy(dx: 16, dy: 16), xRadius: 24, yRadius: 24)
        NSColor(calibratedWhite: 1, alpha: 0.94).setFill()
        bubble.fill()

        let title = NSAttributedString(
            string: "Cat sprite missing",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 20),
                .foregroundColor: NSColor.labelColor
            ]
        )
        title.draw(at: NSPoint(x: 32, y: rect.midY - 6))
    }

    deinit {
        displayTimer?.invalidate()
    }

    private static func buildPoses(external: ExternalPaths) -> [Pose: PoseDefinition] {
        let recline = external.loadSprite(named: "cat_idle_recline_v1.png")
        let loaf = external.loadSprite(named: "cat_idle_loaf_v1.png")
        let sit = external.loadSprite(named: "cat_sit_v1.png")
        let sleep = external.loadSprite(named: "cat_sleep_curl_v1.png")
        let walkBase = [
            external.loadSprite(named: "cat_walk_01_v1.png"),
            external.loadSprite(named: "cat_walk_01b_v1.png"),
            external.loadSprite(named: "cat_walk_02_v1.png"),
            external.loadSprite(named: "cat_walk_03_v1.png"),
            external.loadSprite(named: "cat_walk_03b_v1.png"),
            external.loadSprite(named: "cat_walk_04_v1.png")
        ].compactMap { $0 }
        let walk = buildWalkLoop(from: walkBase)

        var poses: [Pose: PoseDefinition] = [:]
        if let recline {
            poses[.recline] = PoseDefinition(frames: [recline], frameDuration: 0.2, stateDuration: 7.0)
        }
        if let loaf {
            poses[.loaf] = PoseDefinition(frames: [loaf], frameDuration: 0.2, stateDuration: 6.5)
        }
        if let sit {
            poses[.sit] = PoseDefinition(frames: [sit], frameDuration: 0.2, stateDuration: 5.8)
            poses[.play] = PoseDefinition(frames: [sit], frameDuration: 0.2, stateDuration: 4.6)
            poses[.beg] = PoseDefinition(frames: [sit], frameDuration: 0.2, stateDuration: 4.0)
        }
        if let recline {
            poses[.stretch] = PoseDefinition(frames: [recline], frameDuration: 0.2, stateDuration: 4.2)
        }
        if !walk.isEmpty {
            poses[.walk] = PoseDefinition(frames: walk, frameDuration: 0.115, stateDuration: 9.4)
        }
        if let sleep {
            poses[.sleep] = PoseDefinition(frames: [sleep], frameDuration: 0.2, stateDuration: 8.0)
        }
        return poses
    }

    private static func buildPoseOrder(from poses: [Pose: PoseDefinition]) -> [Pose] {
        let available = Set(poses.filter { !$0.value.frames.isEmpty }.map(\.key))
        let filtered = preferredPoseOrder.filter { available.contains($0) }
        if !filtered.isEmpty {
            return filtered
        }
        return available.isEmpty ? [.recline] : Array(available)
    }

    private static func buildWalkLoop(from frames: [NSImage]) -> [NSImage] {
        guard frames.count >= 6 else { return frames }
        return [
            frames[0],
            frames[1],
            frames[2],
            frames[3],
            frames[4],
            frames[5],
            frames[4],
            frames[2]
        ]
    }
}


private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
