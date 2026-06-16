import AppKit
import UniformTypeIdentifiers

struct PetImportStudioResult {
    let pack: GeneratedPetPack
    let sourceImageURL: URL
}

final class PetImportStudioWindowController: NSWindowController {
    private let generator: PetAssetGenerating
    private let rootURL: URL

    private var result: PetImportStudioResult?
    private var imageURLs: [URL] = []
    private var generationCancelled = false

    private let imageListLabel = NSTextField(labelWithString: L("还没有添加参考图", "No reference images yet"))
    private let petNameField = NSTextField()
    private let stylePopup = NSPopUpButton()
    private let notesTextView = NSTextView()
    private let promptPreview = NSTextField(wrappingLabelWithString: "")
    private let generateButton = NSButton()

    init(generator: PetAssetGenerating, rootURL: URL) {
        self.generator = generator
        self.rootURL = rootURL

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("宠物导入工作台", "Pet Import Studio")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.82, alpha: 1)

        super.init(window: window)
        window.delegate = self
        window.contentView = buildContentView()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func runModal() -> PetImportStudioResult? {
        guard let window else { return nil }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        refreshPromptPreview()
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return result
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
        stack.addArrangedSubview(bodyView())
        stack.addArrangedSubview(footerView())
        return root
    }

    private func headerView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading

        let eyebrow = NSTextField(labelWithString: L("创建桌面宠物", "CREATE A DESKTOP PET"))
        eyebrow.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        eyebrow.textColor = NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.16, alpha: 1)
        stack.addArrangedSubview(eyebrow)

        let title = NSTextField(labelWithString: L("添加参考图，配置风格，然后生成", "Import references, define the look, then generate"))
        title.font = .systemFont(ofSize: 27, weight: .bold)
        title.textColor = NSColor(calibratedRed: 0.15, green: 0.10, blue: 0.07, alpha: 1)
        stack.addArrangedSubview(title)

        let aiEnabled = AIModelSettingsStore.shared.load().isEnabled
        let copyText = aiEnabled
            ? L("添加参考图后点击生成，AI 会为每个姿态单独生成高质量素材图。走路帧由本地派生。",
                "Add reference images and generate. AI will create high-quality sprites for each pose. Walk frames are derived locally.")
            : L("如果有多张图可以一起添加。当前会使用第一张图本地生成。配置 AI 模型后可用 AI 生成更好的效果。",
                "Add images and generate. Currently uses the first image for local generation. Configure an AI model for better results.")
        let copy = NSTextField(wrappingLabelWithString: copyText)
        copy.font = .systemFont(ofSize: 13)
        copy.textColor = NSColor(calibratedRed: 0.39, green: 0.30, blue: 0.22, alpha: 1)
        copy.widthAnchor.constraint(equalToConstant: 780).isActive = true
        stack.addArrangedSubview(copy)

        return stack
    }

    private func bodyView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 18
        row.alignment = .top

        row.addArrangedSubview(referenceCard())
        row.addArrangedSubview(promptCard())
        return row
    }

    private func referenceCard() -> NSView {
        let card = cardStack(width: 360)
        card.addArrangedSubview(sectionTitle(L("1. 参考图片", "1. Reference Images")))

        let addButton = NSButton(title: L("添加参考图片...", "Add Reference Images..."), target: self, action: #selector(addReferenceImages))
        addButton.bezelStyle = .rounded
        addButton.controlSize = .large
        card.addArrangedSubview(addButton)

        imageListLabel.font = .systemFont(ofSize: 12)
        imageListLabel.textColor = NSColor(calibratedRed: 0.45, green: 0.34, blue: 0.25, alpha: 1)
        imageListLabel.lineBreakMode = .byTruncatingMiddle
        imageListLabel.widthAnchor.constraint(equalToConstant: 310).isActive = true
        card.addArrangedSubview(imageListLabel)

        let hint = NSTextField(wrappingLabelWithString: L("后续模型模式最适合的输入：正面、侧面、坐姿、睡姿、脸部/细节图。当前本地兜底只会使用第一张图生成。", "Best input later for model mode: front, side, sitting, sleeping, and a clear face/detail shot. For now, the local fallback generates from the first image."))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor(calibratedRed: 0.52, green: 0.40, blue: 0.30, alpha: 1)
        hint.widthAnchor.constraint(equalToConstant: 310).isActive = true
        card.addArrangedSubview(hint)

        return card
    }

    private func promptCard() -> NSView {
        let card = cardStack(width: 460)
        card.addArrangedSubview(sectionTitle(L("2. 提示词配置", "2. Prompt Configuration")))

        petNameField.placeholderString = L("宠物名称，例如：Mochi", "Pet name, e.g. Mochi")
        petNameField.font = .systemFont(ofSize: 13)
        petNameField.widthAnchor.constraint(equalToConstant: 410).isActive = true
        petNameField.target = self
        petNameField.action = #selector(fieldChanged)
        card.addArrangedSubview(labeledControl(L("名称", "Name"), petNameField))

        stylePopup.addItems(withTitles: styleOptions().map(\.title))
        stylePopup.target = self
        stylePopup.action = #selector(fieldChanged)
        card.addArrangedSubview(labeledControl(L("风格", "Style"), stylePopup))

        notesTextView.string = L("保持同一个角色身份、花纹、比例和性格。透明背景。不要文字。不要额外物体。", "Keep the same character identity, markings, proportions, and personality. Transparent background. No text. No extra objects.")
        notesTextView.font = .systemFont(ofSize: 12)
        notesTextView.textColor = NSColor(calibratedRed: 0.24, green: 0.18, blue: 0.13, alpha: 1)
        notesTextView.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.92, alpha: 1)
        notesTextView.delegate = self
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 410, height: 86))
        scroll.hasVerticalScroller = true
        scroll.documentView = notesTextView
        scroll.widthAnchor.constraint(equalToConstant: 410).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 86).isActive = true
        card.addArrangedSubview(labeledControl(L("提示词备注", "Prompt notes"), scroll))

        promptPreview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        promptPreview.textColor = NSColor(calibratedRed: 0.43, green: 0.31, blue: 0.21, alpha: 1)
        promptPreview.widthAnchor.constraint(equalToConstant: 410).isActive = true
        card.addArrangedSubview(labeledControl(L("自动生成的提示词", "Generated prompt"), promptPreview))

        return card
    }

    private func footerView() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let aiEnabled = AIModelSettingsStore.shared.load().isEnabled
        let hintText = aiEnabled
            ? L("AI 模式会调用模型 API 生成 4 个关键姿态，走路帧由本地派生。如失败会自动回退本地生成。",
                "AI mode calls the model API for 4 key poses; walk frames are derived locally. Falls back to local on failure.")
            : L("这里会先生成一个本地候选结果。应用前你还会看到最终预览。",
                "This creates a local candidate first. You will still review the generated pet before applying it.")
        let hint = NSTextField(wrappingLabelWithString: hintText)
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor(calibratedRed: 0.43, green: 0.33, blue: 0.25, alpha: 1)
        hint.widthAnchor.constraint(equalToConstant: 580).isActive = true
        row.addArrangedSubview(hint)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let cancel = NSButton(title: L("取消", "Cancel"), target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        row.addArrangedSubview(cancel)

        generateButton.title = L("生成预览", "Generate Preview")
        generateButton.target = self
        generateButton.action = #selector(generatePreview)
        generateButton.bezelStyle = .rounded
        generateButton.controlSize = .large
        generateButton.widthAnchor.constraint(equalToConstant: 150).isActive = true
        row.addArrangedSubview(generateButton)

        return row
    }

    private func cardStack(width: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .leading
        stack.wantsLayer = true
        stack.layer?.backgroundColor = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.91, alpha: 1).cgColor
        stack.layer?.cornerRadius = 24
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.heightAnchor.constraint(equalToConstant: 390).isActive = true
        return stack
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.textColor = NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.07, alpha: 1)
        return label
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

    @objc private func addReferenceImages() {
        let panel = NSOpenPanel()
        panel.title = L("选择参考图片", "Choose reference images")
        panel.prompt = L("添加", "Add")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["png", "jpg", "jpeg", "heic", "tiff", "webp"].compactMap {
            UTType(filenameExtension: $0)
        }

        guard panel.runModal() == .OK else { return }
        imageURLs.append(contentsOf: panel.urls)
        updateImageList()
    }

    @objc private func generatePreview() {
        guard let primary = imageURLs.first else {
            showInlineAlert(title: L("请至少添加一张图片", "Add at least one image"), message: L("需要至少一张参考图才能生成。", "At least one reference image is needed to generate."))
            return
        }

        generateButton.isEnabled = false
        generationCancelled = false

        let aiSettings = AIModelSettingsStore.shared.load()
        let apiKey = AIModelSettingsStore.shared.loadAPIKey()
        let useAI = aiSettings.isEnabled
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !aiSettings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if useAI {
            generateButton.title = L("AI 生成中 0/10...", "AI generating 0/10...")
            let petName = petNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let style = selectedStylePrompt()
            let notes = notesTextView.string
            let rootURL = self.rootURL
            let localGenerator = self.generator

            let imageURLsCopy = self.imageURLs

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let aiGenerator = AIPackGenerator(
                    settings: aiSettings,
                    apiKey: apiKey,
                    petName: petName,
                    style: style,
                    notes: notes,
                    imageURLs: imageURLsCopy
                )
                aiGenerator.onProgress = { [weak self] status in
                    DispatchQueue.main.async { self?.generateButton.title = status }
                }
                aiGenerator.isCancelled = { [weak self] in self?.generationCancelled ?? true }

                do {
                    let pack = try aiGenerator.generatePetPack(from: primary, rootURL: rootURL)
                    DispatchQueue.main.async {
                        self?.finishGeneration(pack: pack, primary: primary, generatorMode: "ai-api-v1")
                    }
                } catch AIPackGeneratorError.cancelled {
                    DispatchQueue.main.async {
                        self?.generateButton.isEnabled = true
                        self?.generateButton.title = L("生成预览", "Generate Preview")
                    }
                } catch {
                    debugLog("AI generation failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.generateButton.title = L("AI 失败，本地生成中...", "AI failed, local fallback...")
                    }
                    do {
                        let pack = try localGenerator.generatePetPack(from: primary, rootURL: rootURL)
                        DispatchQueue.main.async {
                            self?.finishGeneration(pack: pack, primary: primary, generatorMode: "local-fallback-after-ai-failure")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self?.generateButton.isEnabled = true
                            self?.generateButton.title = L("生成预览", "Generate Preview")
                            self?.showInlineAlert(title: L("生成失败", "Generation failed"), message: error.localizedDescription)
                        }
                    }
                }
            }
        } else {
            generateButton.title = L("生成中...", "Generating...")
            defer {
                generateButton.isEnabled = true
                generateButton.title = L("生成预览", "Generate Preview")
            }
            do {
                let pack = try generator.generatePetPack(from: primary, rootURL: rootURL)
                finishGeneration(pack: pack, primary: primary, generatorMode: "local-fallback-first-image")
            } catch {
                showInlineAlert(title: L("生成失败", "Generation failed"), message: error.localizedDescription)
            }
        }
    }

    private func finishGeneration(pack: GeneratedPetPack, primary: URL, generatorMode: String) {
        generateButton.isEnabled = true
        generateButton.title = L("生成预览", "Generate Preview")
        do {
            try writeImportConfiguration(to: pack.directory, generatorMode: generatorMode)
            result = PetImportStudioResult(pack: pack, sourceImageURL: primary)
            closeModal()
        } catch {
            showInlineAlert(title: L("生成失败", "Generation failed"), message: error.localizedDescription)
        }
    }

    @objc private func cancel() {
        generationCancelled = true
        result = nil
        closeModal()
    }

    @objc private func fieldChanged() {
        refreshPromptPreview()
    }

    private func updateImageList() {
        if imageURLs.isEmpty {
            imageListLabel.stringValue = L("还没有添加参考图", "No reference images yet")
        } else {
            let names = imageURLs.prefix(4).map(\.lastPathComponent).joined(separator: "\n")
            let suffix = imageURLs.count > 4 ? L("\n另外 \(imageURLs.count - 4) 张", "\n+\(imageURLs.count - 4) more") : ""
            imageListLabel.stringValue = L("\(imageURLs.count) 张图片\n\(names)\(suffix)", "\(imageURLs.count) image(s)\n\(names)\(suffix)")
        }
    }

    private func refreshPromptPreview() {
        promptPreview.stringValue = generatedPrompt()
    }

    private func generatedPrompt() -> String {
        let name = petNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let petName = name.isEmpty ? L("这个宠物", "this pet") : name
        let style = selectedStylePrompt()
        return L(
            "为 \(petName) 创建一套透明背景桌宠素材包。风格：\(style)。动作：待机、坐下、趴着、睡觉、六帧走路。\(notesTextView.string)",
            "Create a transparent-background desktop pet sprite pack for \(petName). Style: \(style). Poses: idle, sit, loaf, sleep, six-frame walk. \(notesTextView.string)"
        )
    }

    private func styleOptions() -> [(title: String, prompt: String)] {
        [
            (L("真实照片", "Realistic photo"), "Realistic photograph, photorealistic, same real cat, natural lighting, high detail"),
            (L("柔和贴纸插画", "Soft sticker illustration"), "Soft sticker illustration"),
            (L("像素风精灵", "Pixel art sprite"), "Pixel art sprite"),
            (L("3D 毛绒玩具", "3D plush toy"), "3D plush toy"),
            (L("干净扁平吉祥物", "Clean flat mascot"), "Clean flat mascot"),
            (L("水彩绘本风", "Watercolor storybook"), "Watercolor storybook")
        ]
    }

    private func selectedStylePrompt() -> String {
        let index = stylePopup.indexOfSelectedItem
        let options = styleOptions()
        guard options.indices.contains(index) else {
            return options.first?.prompt ?? "Soft sticker illustration"
        }
        return options[index].prompt
    }

    private func writeImportConfiguration(to directory: URL, generatorMode: String = "local-fallback-first-image") throws {
        let payload: [String: Any] = [
            "schema": 1,
            "pet_name": petNameField.stringValue,
            "style": selectedStylePrompt(),
            "prompt": generatedPrompt(),
            "reference_images": imageURLs.map(\.path),
            "generator_mode": generatorMode,
            "future_model_input_ready": true
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("import-config.json"), options: .atomic)
    }

    private func showInlineAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window ?? NSWindow()) { _ in }
    }

    private func closeModal() {
        if let window {
            NSApp.stopModal()
            window.close()
        }
    }
}

extension PetImportStudioWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        refreshPromptPreview()
    }
}

extension PetImportStudioWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.stopModal()
    }
}
