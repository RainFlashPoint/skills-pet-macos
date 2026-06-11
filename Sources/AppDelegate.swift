import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var petWindow: PetWindow?
    private var aiSettingsWindow: AIModelSettingsWindowController?
    private let external = ExternalPaths()
    private let petPackGenerator: PetAssetGenerating = PetPackGenerator()
    private var visibilityTimer: Timer?
    private var frontingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("applicationDidFinishLaunching start")
        NSApp.setActivationPolicy(.accessory)
        ensurePetWindow(forceCenter: true)
        setupStatusItem()
        startVisibilityWatchdog()
        startFrontingWatchdog()
        debugLog("status item ready")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc private func openHub() {
        external.openHub()
    }

    @objc private func openCatalog() {
        external.openCatalog()
    }

    @objc private func openAIModelSettings() {
        let controller = AIModelSettingsWindowController()
        aiSettingsWindow = controller
        controller.show()
    }

    @objc private func importPetImage() {
        NSApp.activate(ignoringOtherApps: true)

        guard let candidate = PetImportStudioWindowController(
            generator: petPackGenerator,
            rootURL: external.petPacksRootURL
        ).runModal() else { return }

        if confirmPetPackPreview(candidate.pack, sourceImageURL: candidate.sourceImageURL) {
            external.selectPetPack(named: candidate.pack.name)
            reloadPetWindow(forceCenter: true)
            showMessage(title: L("宠物已导入", "Pet Imported"), message: L("已选择宠物包：\(candidate.pack.name)", "Selected pet pack: \(candidate.pack.name)"))
        } else {
            deleteGeneratedPetPack(candidate.pack)
        }
    }

    @objc private func useDefaultCat() {
        external.clearSelectedPetPack()
        reloadPetWindow(forceCenter: false)
    }

    @objc private func setChineseLanguage() {
        setLanguage(.zh)
    }

    @objc private func setEnglishLanguage() {
        setLanguage(.en)
    }

    @objc private func recenterPet() {
        ensurePetWindow(forceCenter: false)
        petWindow?.setBehaviorMode(.roaming)
        petWindow?.moveToVisibleCenter()
        refreshStatusMenu()
    }

    @objc private func showPet() {
        ensurePetWindow(forceCenter: true)
    }

    @objc private func setRoamingMode() {
        setPetMode(.roaming)
    }

    @objc private func setDockedMode() {
        setPetMode(.docked)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Pet"
        statusItem = item
        refreshStatusMenu()
    }

    private func startVisibilityWatchdog() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.ensurePetWindow(forceCenter: false)
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        visibilityTimer = timer
    }

    private func startFrontingWatchdog() {
        let timer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in
            guard let petWindow = self?.petWindow, petWindow.isVisible else { return }
            petWindow.orderFrontRegardless()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        frontingTimer = timer
    }

    private func ensurePetWindow(forceCenter: Bool) {
        if petWindow == nil {
            debugLog("ensurePetWindow creating new window")
            petWindow = PetWindow(external: external)
        }

        guard let petWindow else { return }
        let revived = petWindow.reviveIfNeeded(forceCenter: forceCenter)
        if revived {
            debugLog("ensurePetWindow revived existing window")
        }

        if !petWindow.isVisible {
            debugLog("ensurePetWindow recreating invisible window")
            self.petWindow = PetWindow(external: external)
            self.petWindow?.reviveIfNeeded(forceCenter: true)
        }

        debugLog("petWindow assigned: \(self.petWindow != nil)")
    }

    private func reloadPetWindow(forceCenter: Bool) {
        petWindow?.orderOut(nil)
        petWindow = PetWindow(external: external)
        petWindow?.reviveIfNeeded(forceCenter: forceCenter)
        refreshStatusMenu()
    }

    private func setPetMode(_ mode: PetBehaviorMode) {
        ensurePetWindow(forceCenter: false)
        petWindow?.setBehaviorMode(mode)
        refreshStatusMenu()
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = title.contains("Failed") || title.contains("失败") ? .warning : .informational
        alert.runModal()
    }

    private func confirmPetPackPreview(_ pack: GeneratedPetPack, sourceImageURL: URL) -> Bool {
        PetImportPreviewWindowController(pack: pack, sourceImageURL: sourceImageURL).runModal()
    }

    private func deleteGeneratedPetPack(_ pack: GeneratedPetPack) {
        do {
            try FileManager.default.removeItem(at: pack.directory)
            debugLog("discarded generated pet pack: \(pack.directory.path)")
        } catch {
            debugLog("failed to discard generated pet pack \(pack.directory.path): \(error.localizedDescription)")
        }
    }

    private func refreshStatusMenu() {
        guard let statusItem else { return }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("打开技能中心", "Open Skills Hub"), action: #selector(openHub), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: L("打开技能目录", "Open Catalog"), action: #selector(openCatalog), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: L("导入宠物图片...", "Import Pet Image..."), action: #selector(importPetImage), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: L("AI 模型设置...", "AI Model Settings..."), action: #selector(openAIModelSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L("切回默认猫", "Use Default Cat"), action: #selector(useDefaultCat), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(modeMenuItem())
        menu.addItem(languageMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("显示桌宠", "Show Pet"), action: #selector(showPet), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: L("居中桌宠", "Center Pet"), action: #selector(recenterPet), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L("退出", "Quit"), action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func modeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("模式", "Mode"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L("模式", "Mode"))
        let currentMode = petWindow?.behaviorMode ?? .roaming

        let roamingItem = NSMenuItem(title: PetBehaviorMode.roaming.title, action: #selector(setRoamingMode), keyEquivalent: "")
        roamingItem.target = self
        roamingItem.state = currentMode == .roaming ? .on : .off
        submenu.addItem(roamingItem)

        let dockedItem = NSMenuItem(title: PetBehaviorMode.docked.title, action: #selector(setDockedMode), keyEquivalent: "")
        dockedItem.target = self
        dockedItem.state = currentMode == .docked ? .on : .off
        submenu.addItem(dockedItem)

        item.submenu = submenu
        return item
    }

    private func languageMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("语言", "Language"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: L("语言", "Language"))

        let zhItem = NSMenuItem(title: AppLanguage.zh.title, action: #selector(setChineseLanguage), keyEquivalent: "")
        zhItem.target = self
        zhItem.state = AppLanguage.current == .zh ? .on : .off
        submenu.addItem(zhItem)

        let enItem = NSMenuItem(title: AppLanguage.en.title, action: #selector(setEnglishLanguage), keyEquivalent: "")
        enItem.target = self
        enItem.state = AppLanguage.current == .en ? .on : .off
        submenu.addItem(enItem)

        item.submenu = submenu
        return item
    }

    private func setLanguage(_ language: AppLanguage) {
        AppLanguage.current = language
        refreshStatusMenu()
    }
}

func debugLog(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/skills-pet-macos-debug.log")
    let data = Data(line.utf8)
    if FileManager.default.fileExists(atPath: url.path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    } else {
        try? data.write(to: url)
    }
}

struct ExternalPaths {
    private struct SkillEntry {
        let title: String
        let path: String
        let kind: String
    }

    private struct SpriteAlias {
        let packCandidates: [String]
    }

    private static var cachedPetPackDirectoryPath: String?
    private static var didResolvePetPackDirectory = false
    private static let selectedPetPackKey = "selectedPetPackName"

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop", isDirectory: true)

    var hubURL: URL {
        discoveredCatalogFile(named: "skills_hub.html")
        ?? ensureGeneratedCatalogFile(named: "skills_hub.html", title: L("本地技能中心", "Local Skills Hub"))
        ?? base.appendingPathComponent("skills-catalog/skills_hub.html")
    }

    var catalogURL: URL {
        discoveredCatalogFile(named: "skills_catalog.html")
        ?? ensureGeneratedCatalogFile(named: "skills_catalog.html", title: L("本地技能目录", "Local Skills Catalog"))
        ?? base.appendingPathComponent("skills-catalog/skills_catalog.html")
    }

    var spriteDirectoryURL: URL {
        base.appendingPathComponent("skills-pet-macos/cat-sprites", isDirectory: true)
    }

    var petPacksRootURL: URL {
        home
            .appendingPathComponent("SkillsPetLite", isDirectory: true)
            .appendingPathComponent("pets", isDirectory: true)
    }

    func loadSprite(named fileName: String) -> NSImage? {
        for candidate in resolvedSpriteCandidateURLs(for: fileName) {
            if let image = NSImage(contentsOf: candidate) {
                return processedSprite(from: image)
            }
        }

        let nsName = NSString(string: fileName)
        let resourceName = nsName.deletingPathExtension
        let resourceExt = nsName.pathExtension
        if let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: resourceExt),
           let image = NSImage(contentsOf: bundledURL) {
            debugLog("loaded sprite from bundle fallback: \(fileName)")
            return processedSprite(from: image)
        }

        debugLog("failed to load sprite for name: \(fileName)")
        return nil
    }

    func openHub() {
        openIfPresent(hubURL, label: "skills hub")
    }

    func openCatalog() {
        openIfPresent(catalogURL, label: "skills catalog")
    }

    func selectPetPack(named name: String) {
        UserDefaults.standard.set(name, forKey: Self.selectedPetPackKey)
        Self.cachedPetPackDirectoryPath = nil
        Self.didResolvePetPackDirectory = false
        debugLog("selected pet pack: \(name)")
    }

    func clearSelectedPetPack() {
        UserDefaults.standard.removeObject(forKey: Self.selectedPetPackKey)
        Self.cachedPetPackDirectoryPath = nil
        Self.didResolvePetPackDirectory = false
        debugLog("cleared selected pet pack; using default cat")
    }

    private func openIfPresent(_ url: URL, label: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            debugLog("missing \(label): \(url.path)")
            NSSound.beep()
            return
        }
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            debugLog("failed to open \(label): \(url.path)")
        }
    }

    private func discoveredCatalogFile(named fileName: String) -> URL? {
        for directory in catalogDirectories() {
            let candidate = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func resolvedSpriteCandidateURLs(for fileName: String) -> [URL] {
        var candidates: [URL] = []
        if let petPackDirectory = discoveredPetPackDirectory() {
            let alias = spriteAlias(for: fileName)
            for candidateName in alias.packCandidates {
                candidates.append(petPackDirectory.appendingPathComponent(candidateName))
            }
        }
        candidates.append(spriteDirectoryURL.appendingPathComponent(fileName))
        return candidates
    }

    private func discoveredPetPackDirectory() -> URL? {
        if Self.didResolvePetPackDirectory {
            return Self.cachedPetPackDirectoryPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }

        Self.didResolvePetPackDirectory = true
        let root = petPacksRootURL

        if let selectedName = UserDefaults.standard.string(forKey: Self.selectedPetPackKey) {
            let selectedDirectory = root.appendingPathComponent(selectedName, isDirectory: true)
            if isUsablePetPackDirectory(selectedDirectory) {
                Self.cachedPetPackDirectoryPath = selectedDirectory.path
                debugLog("using selected pet pack: \(selectedDirectory.path)")
                return selectedDirectory
            }
            debugLog("selected pet pack unavailable: \(selectedDirectory.path)")
        }

        return nil
    }

    private func isUsablePetPackDirectory(_ directory: URL) -> Bool {
        guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == true else {
            return false
        }

        let probeNames = [
            "recline.png",
            "idle_recline.png",
            "cat_idle_recline_v1.png",
            "sit.png",
            "cat_sit_v1.png",
            "walk_01.png",
            "cat_walk_01_v1.png"
        ]

        return probeNames.contains { probe in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(probe).path)
        }
    }

    private func spriteAlias(for fileName: String) -> SpriteAlias {
        switch fileName {
        case "cat_idle_recline_v1.png":
            return SpriteAlias(packCandidates: [
                "recline.png",
                "idle_recline.png",
                fileName
            ])
        case "cat_idle_loaf_v1.png":
            return SpriteAlias(packCandidates: [
                "loaf.png",
                "idle_loaf.png",
                fileName
            ])
        case "cat_sit_v1.png":
            return SpriteAlias(packCandidates: [
                "sit.png",
                fileName
            ])
        case "cat_sleep_curl_v1.png":
            return SpriteAlias(packCandidates: [
                "sleep.png",
                "sleep_curl.png",
                fileName
            ])
        case "cat_walk_01_v1.png":
            return SpriteAlias(packCandidates: [
                "walk_01.png",
                fileName
            ])
        case "cat_walk_01b_v1.png":
            return SpriteAlias(packCandidates: [
                "walk_02.png",
                fileName
            ])
        case "cat_walk_02_v1.png":
            return SpriteAlias(packCandidates: [
                "walk_03.png",
                fileName
            ])
        case "cat_walk_03_v1.png":
            return SpriteAlias(packCandidates: [
                "walk_04.png",
                fileName
            ])
        case "cat_walk_03b_v1.png":
            return SpriteAlias(packCandidates: [
                "walk_05.png",
                fileName
            ])
        case "cat_walk_04_v1.png":
            return SpriteAlias(packCandidates: [
                "walk_06.png",
                fileName
            ])
        default:
            return SpriteAlias(packCandidates: [fileName])
        }
    }

    private func ensureGeneratedCatalogFile(named fileName: String, title: String) -> URL? {
        let directory = generatedCatalogDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(fileName)
            let html = generatedCatalogHTML(title: title)
            try html.write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            debugLog("failed to generate \(fileName): \(error.localizedDescription)")
            return nil
        }
    }

    private func generatedCatalogDirectoryURL() -> URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent("SkillsPetLite", isDirectory: true)
    }

    private func generatedCatalogHTML(title: String) -> String {
        let entries = discoveredSkillEntries()
        let body: String
        if entries.isEmpty {
            body = """
            <div class="empty">
              <h2>\(htmlEscape(L("没有找到本地技能", "No local skills found")))</h2>
              <p>\(htmlEscape(L("可以把技能目录放到 ~/Desktop/skills 或 ~/Desktop/skills-catalog 这类文件夹下。", "Put your skills under folders like ~/Desktop/skills or ~/Desktop/skills-catalog.")))</p>
            </div>
            """
        } else {
            body = entries.map { entry in
                """
                <li class="card">
                  <div class="meta">\(htmlEscape(entry.kind))</div>
                  <div class="title">\(htmlEscape(entry.title))</div>
                  <div class="path">\(htmlEscape(entry.path))</div>
                </li>
                """
            }.joined(separator: "\n")
        }

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(title))</title>
          <style>
            :root { color-scheme: light; }
            body {
              margin: 0;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
              background: linear-gradient(180deg, #f6f2eb 0%, #fffdf8 100%);
              color: #1f1f1f;
            }
            main {
              max-width: 920px;
              margin: 0 auto;
              padding: 32px 20px 48px;
            }
            h1 {
              margin: 0 0 10px;
              font-size: 32px;
            }
            p {
              margin: 0 0 24px;
              color: #5f5b54;
              line-height: 1.5;
            }
            ul {
              list-style: none;
              padding: 0;
              margin: 0;
              display: grid;
              gap: 12px;
            }
            .card, .empty {
              background: rgba(255,255,255,0.82);
              border: 1px solid rgba(96,79,56,0.12);
              border-radius: 18px;
              padding: 16px 18px;
              box-shadow: 0 10px 30px rgba(82, 64, 41, 0.08);
              backdrop-filter: blur(8px);
            }
            .meta {
              font-size: 12px;
              text-transform: uppercase;
              letter-spacing: 0.08em;
              color: #8f6f48;
              margin-bottom: 6px;
            }
            .title {
              font-size: 18px;
              font-weight: 600;
              margin-bottom: 6px;
            }
            .path, code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              font-size: 12px;
              color: #645a50;
              word-break: break-all;
            }
          </style>
        </head>
        <body>
          <main>
            <h1>\(htmlEscape(title))</h1>
            <p>\(htmlEscape(L("根据本机看起来像技能目录的文件夹自动生成。如果已经有手写 HTML 文件，会优先使用手写版本。", "Auto-generated from local folders that look like skills directories. Existing handwritten HTML still wins if found.")))</p>
            <ul>
              \(body)
            </ul>
          </main>
        </body>
        </html>
        """
    }

    private func discoveredSkillEntries() -> [SkillEntry] {
        let interestingExtensions = Set(["md", "html", "json", "py", "js", "ts", "swift", "txt"])
        var results: [SkillEntry] = []

        for directory in catalogDirectories() {
            let name = directory.lastPathComponent
            results.append(SkillEntry(title: name, path: directory.path, kind: "folder"))

            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - directory.pathComponents.count
                if depth > 2 {
                    enumerator.skipDescendants()
                    continue
                }

                let ext = url.pathExtension.lowercased()
                if interestingExtensions.contains(ext) {
                    results.append(SkillEntry(title: url.lastPathComponent, path: url.path, kind: ext))
                }
            }
        }

        var deduped: [SkillEntry] = []
        var seen = Set<String>()
        for entry in results {
            if seen.insert(entry.path).inserted {
                deduped.append(entry)
            }
        }
        return deduped.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private func catalogDirectories() -> [URL] {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let commonCandidates = [
            desktop.appendingPathComponent("skills-catalog", isDirectory: true),
            desktop.appendingPathComponent("skills", isDirectory: true),
            documents.appendingPathComponent("skills-catalog", isDirectory: true),
            documents.appendingPathComponent("skills", isDirectory: true),
            home.appendingPathComponent("skills-catalog", isDirectory: true),
            home.appendingPathComponent("skills", isDirectory: true)
        ]

        var ordered = commonCandidates
        let roots = [desktop, documents, home]
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for child in children where child.lastPathComponent.lowercased().contains("skill") {
                ordered.append(child)
            }
        }

        var deduped: [URL] = []
        var seen = Set<String>()
        for url in ordered {
            if seen.insert(url.path).inserted {
                deduped.append(url)
            }
        }
        return deduped
    }

    private func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func processedSprite(from image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: rect)

        guard let data = context.data else {
            return image
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * bytesPerPixel)
        for index in stride(from: 0, to: width * height * bytesPerPixel, by: bytesPerPixel) {
            let alpha = Int(pixels[index + 3])
            if alpha == 0 {
                continue
            }

            if alpha < 28 {
                pixels[index + 3] = 0
                continue
            }

            if alpha < 168 {
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])
                let maxChannel = max(red, max(green, blue))
                let minChannel = min(red, min(green, blue))
                let isNearWhite = maxChannel > 214 && (maxChannel - minChannel) < 26
                if isNearWhite {
                    pixels[index + 3] = UInt8(max(0, alpha - 72))
                } else if alpha < 96 {
                    pixels[index + 3] = UInt8(max(0, alpha - 24))
                }
            }
        }

        guard let processedCGImage = context.makeImage() else {
            return image
        }

        let processed = NSImage(cgImage: processedCGImage, size: image.size)
        processed.isTemplate = false
        return processed
    }
}
