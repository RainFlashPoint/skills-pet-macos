import AppKit

final class PetImportPreviewWindowController: NSWindowController {
    private var accepted = false
    private var animatedPreview: AnimatedPetPreviewView?

    private let pack: GeneratedPetPack
    private let sourceImageURL: URL

    init(pack: GeneratedPetPack, sourceImageURL: URL) {
        self.pack = pack
        self.sourceImageURL = sourceImageURL

        let contentRect = NSRect(x: 0, y: 0, width: 940, height: 680)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("确认宠物导入", "Review Pet Import")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.84, alpha: 1)

        super.init(window: window)
        window.contentView = buildContentView()
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func runModal() -> Bool {
        guard let window else { return false }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return accepted
    }

    private func buildContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.96, green: 0.92, blue: 0.84, alpha: 1).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 18
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22)
        ])

        stack.addArrangedSubview(headerView())
        stack.addArrangedSubview(mainPreviewView())
        stack.addArrangedSubview(footerView())
        return root
    }

    private func headerView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 7
        container.alignment = .leading

        let eyebrow = NSTextField(labelWithString: L("宠物导入工作台", "PET IMPORT STUDIO"))
        eyebrow.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.17, alpha: 1)
        container.addArrangedSubview(eyebrow)

        let title = NSTextField(labelWithString: L("应用前检查生成效果", "Check the generated pet before it goes live"))
        title.font = .systemFont(ofSize: 27, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.16, green: 0.11, blue: 0.07, alpha: 1)
        container.addArrangedSubview(title)

        let copy = NSTextField(wrappingLabelWithString: L("当前本地流程会裁剪简单背景并生成程序化动作变体。如果抠图或动作不对，请取消。后续模型 API 也会复用这个确认步骤。", "The current local pipeline crops simple backgrounds and creates procedural pose variants. If the cutout or pose looks wrong, cancel it. The model API pipeline will plug into the same review step later."))
        copy.font = .systemFont(ofSize: 13)
        copy.textColor = NSColor(calibratedRed: 0.40, green: 0.31, blue: 0.23, alpha: 1)
        copy.maximumNumberOfLines = 2
        copy.widthAnchor.constraint(equalToConstant: 780).isActive = true
        container.addArrangedSubview(copy)

        return container
    }

    private func mainPreviewView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 18
        row.alignment = .top
        row.distribution = .fill

        row.addArrangedSubview(tile(title: L("原始上传图", "Original upload"), subtitle: sourceImageURL.lastPathComponent, imageURL: sourceImageURL, width: 300, height: 384, emphasis: true))

        let generatedPanel = NSStackView()
        generatedPanel.orientation = .vertical
        generatedPanel.spacing = 12
        generatedPanel.alignment = .leading
        generatedPanel.wantsLayer = true
        generatedPanel.layer?.backgroundColor = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.91, alpha: 1).cgColor
        generatedPanel.layer?.cornerRadius = 24
        generatedPanel.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let label = NSTextField(labelWithString: L("生成的宠物包：\(pack.name)", "Generated pack: \(pack.name)"))
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.08, alpha: 1)
        generatedPanel.addArrangedSubview(label)

        let gridTop = NSStackView()
        gridTop.orientation = .horizontal
        gridTop.spacing = 12
        gridTop.addArrangedSubview(tile(title: L("待机", "Idle"), subtitle: L("基础姿态", "base pose"), imageURL: pack.directory.appendingPathComponent("recline.png"), width: 250, height: 166))
        gridTop.addArrangedSubview(animatedTile())
        generatedPanel.addArrangedSubview(gridTop)

        let gridBottom = NSStackView()
        gridBottom.orientation = .horizontal
        gridBottom.spacing = 12
        gridBottom.addArrangedSubview(tile(title: L("坐下", "Sit"), subtitle: L("直立变体", "upright variant"), imageURL: pack.directory.appendingPathComponent("sit.png"), width: 162, height: 136))
        gridBottom.addArrangedSubview(tile(title: L("趴着", "Loaf"), subtitle: L("休息变体", "rest variant"), imageURL: pack.directory.appendingPathComponent("loaf.png"), width: 162, height: 136))
        gridBottom.addArrangedSubview(tile(title: L("走路", "Walk"), subtitle: L("动作帧", "motion frame"), imageURL: pack.directory.appendingPathComponent("walk_03.png"), width: 162, height: 136))
        generatedPanel.addArrangedSubview(gridBottom)

        row.addArrangedSubview(generatedPanel)
        return row
    }

    private func animatedTile() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 8
        container.alignment = .leading

        let frameURLs = (1 ... 6).map { pack.directory.appendingPathComponent("walk_0\($0).png") }
        let preview = AnimatedPetPreviewView(frame: NSRect(x: 0, y: 0, width: 250, height: 166), imageURLs: frameURLs)
        animatedPreview = preview
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 18
        preview.layer?.masksToBounds = true
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor(calibratedRed: 0.74, green: 0.50, blue: 0.25, alpha: 0.28).cgColor
        preview.widthAnchor.constraint(equalToConstant: 250).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 166).isActive = true
        container.addArrangedSubview(preview)

        let text = NSStackView()
        text.orientation = .vertical
        text.spacing = 1
        text.alignment = .leading
        let titleLabel = NSTextField(labelWithString: L("走路预览", "Walk Preview"))
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.08, alpha: 1)
        text.addArrangedSubview(titleLabel)
        let subtitleLabel = NSTextField(labelWithString: L("程序化循环动画", "animated procedural loop"))
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor(calibratedRed: 0.51, green: 0.39, blue: 0.29, alpha: 1)
        text.addArrangedSubview(subtitleLabel)
        container.addArrangedSubview(text)

        return container
    }

    private func tile(title: String, subtitle: String, imageURL: URL, width: CGFloat, height: CGFloat, emphasis: Bool = false) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 8
        container.alignment = .leading

        let imageView = CheckerboardImageView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        imageView.image = NSImage(contentsOf: imageURL)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = emphasis ? 24 : 18
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = emphasis ? 2 : 1
        imageView.layer?.borderColor = NSColor(calibratedRed: 0.74, green: 0.50, blue: 0.25, alpha: emphasis ? 0.7 : 0.28).cgColor
        imageView.widthAnchor.constraint(equalToConstant: width).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: height).isActive = true
        container.addArrangedSubview(imageView)

        let text = NSStackView()
        text.orientation = .vertical
        text.spacing = 1
        text.alignment = .leading

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.08, alpha: 1)
        text.addArrangedSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor(calibratedRed: 0.51, green: 0.39, blue: 0.29, alpha: 1)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.widthAnchor.constraint(equalToConstant: width).isActive = true
        text.addArrangedSubview(subtitleLabel)

        container.addArrangedSubview(text)
        return container
    }

    private func footerView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let hint = NSTextField(wrappingLabelWithString: L("如果主体太小、背景残留明显，或者动作看起来不对，请取消。确认前不会应用到桌宠。", "Cancel if the subject is tiny, background remains visible, or the generated poses feel broken. Nothing is applied until you approve."))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.25, alpha: 1)
        hint.widthAnchor.constraint(equalToConstant: 560).isActive = true
        row.addArrangedSubview(hint)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let cancel = button(title: L("取消", "Cancel"), filled: false, action: #selector(cancelImport))
        let accept = button(title: L("使用这个宠物", "Use This Pet"), filled: true, action: #selector(acceptImport))
        row.addArrangedSubview(cancel)
        row.addArrangedSubview(accept)
        return row
    }

    private func button(title: String, filled: Bool, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.controlSize = .large
        button.widthAnchor.constraint(equalToConstant: filled ? 138 : 104).isActive = true
        return button
    }

    @objc private func acceptImport() {
        accepted = true
        if let window {
            NSApp.stopModal(withCode: .OK)
            window.close()
        }
    }

    @objc private func cancelImport() {
        accepted = false
        if let window {
            NSApp.stopModal(withCode: .cancel)
            window.close()
        }
    }
}

extension PetImportPreviewWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        animatedPreview?.stop()
        NSApp.stopModal(withCode: accepted ? .OK : .cancel)
    }
}

private final class CheckerboardImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        drawCheckerboard(in: bounds)
        super.draw(dirtyRect)
    }

    private func drawCheckerboard(in rect: NSRect) {
        let base = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.88, alpha: 1)
        let mark = NSColor(calibratedRed: 0.90, green: 0.84, blue: 0.73, alpha: 1)
        base.setFill()
        rect.fill()

        let size: CGFloat = 16
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var column = 0
            while x < rect.maxX {
                if (row + column).isMultiple(of: 2) {
                    mark.setFill()
                    NSRect(x: x, y: y, width: size, height: size).fill()
                }
                x += size
                column += 1
            }
            y += size
            row += 1
        }
    }
}

private final class AnimatedPetPreviewView: NSView {
    private let images: [NSImage]
    private var frameIndex = 0
    private var timer: Timer?
    private var motionPhase: CGFloat = 0

    init(frame frameRect: NSRect, imageURLs: [URL]) {
        self.images = imageURLs.compactMap(NSImage.init(contentsOf:))
        super.init(frame: frameRect)
        wantsLayer = true
        start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCheckerboard(in: bounds)
        guard !images.isEmpty else { return }

        let image = images[frameIndex % images.count]
        let maxWidth = bounds.width * 0.82
        let maxHeight = bounds.height * 0.78
        let scale = min(maxWidth / image.size.width, maxHeight / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let bob = abs(sin(motionPhase)) * 10
        let sway = sin(motionPhase * 0.7) * 12
        let rect = NSRect(
            x: (bounds.width - size.width) / 2 + sway,
            y: (bounds.height - size.height) / 2 + bob,
            width: size.width,
            height: size.height
        )

        NSColor(calibratedWhite: 0.08, alpha: 0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - 58, y: 16, width: 116, height: 12)).fill()
        image.draw(in: rect)
    }

    func start() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            frameIndex = (frameIndex + 1) % max(1, images.count)
            motionPhase += 0.55
            needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stop()
    }

    private func drawCheckerboard(in rect: NSRect) {
        let base = NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.88, alpha: 1)
        let mark = NSColor(calibratedRed: 0.90, green: 0.84, blue: 0.73, alpha: 1)
        base.setFill()
        rect.fill()

        let size: CGFloat = 16
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var column = 0
            while x < rect.maxX {
                if (row + column).isMultiple(of: 2) {
                    mark.setFill()
                    NSRect(x: x, y: y, width: size, height: size).fill()
                }
                x += size
                column += 1
            }
            y += size
            row += 1
        }
    }
}
