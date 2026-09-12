import AppKit

private func sizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// AppKit keeps the compatibility build independent of SwiftUI and Swift concurrency.
@main
struct CatalinaMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = CatalinaApp()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class CatalinaApp: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var window: NSWindow!
    private let title = NSTextField(labelWithString: "Choose a folder to explore storage")
    private let metrics = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "Ready · Intel / macOS Catalina")
    private let search = NSSearchField()
    private let table = NSTableView()
    private let progress = NSProgressIndicator()
    private let chart = StorageChart()
    private var controls: [NSControl] = []
    private var cancelButton: NSButton!
    private var result: ScanResult?
    private var current = 0
    private var rows: [ScanNode] = []
    private var token: ScanCancellation?
    private var busy = false
    private var aiReport: AIReport?
    private var aiRoot: URL?
    private var reportWindow: ReportWindow?
    private var cleanupWindow: ReportWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Disk Checker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(); item.submenu = appMenu; menu.addItem(item)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        NSApplication.shared.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 730), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Disk Checker — Catalina"
        window.minSize = NSSize(width: 950, height: 620)
        window.isReleasedWhenClosed = false
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20)
        ])
        let heading = NSTextField(labelWithString: "Disk Checker")
        heading.font = .boldSystemFont(ofSize: 26)
        root.addArrangedSubview(heading)
        let toolbar = NSStackView(); toolbar.spacing = 8
        toolbar.addArrangedSubview(button("Scan Folder…", #selector(chooseFolder)))
        let quick = NSPopUpButton(); quick.addItems(withTitles: ["Quick Scan…", "Home", "Desktop", "Documents", "Downloads", "Applications"])
        quick.target = self; quick.action = #selector(quickScan(_:)); controls.append(quick)
        toolbar.addArrangedSubview(quick)
        toolbar.addArrangedSubview(button("Rescan", #selector(rescan)))
        toolbar.addArrangedSubview(button("Check AI Metadata…", #selector(checkAI)))
        toolbar.addArrangedSubview(button("AI Results…", #selector(showAIResults)))
        toolbar.addArrangedSubview(button("Desktop Screenshots…", #selector(screenshots)))
        root.addArrangedSubview(toolbar)
        title.font = .boldSystemFont(ofSize: 14); title.isSelectable = true; title.lineBreakMode = .byTruncatingMiddle
        root.addArrangedSubview(title)
        metrics.font = .systemFont(ofSize: 13); root.addArrangedSubview(metrics)
        chart.heightAnchor.constraint(equalToConstant: 25).isActive = true
        chart.open = { [weak self] node in self?.open(node) }
        root.addArrangedSubview(chart)
        let navigation = NSStackView(); navigation.spacing = 8
        navigation.addArrangedSubview(button("Up", #selector(goUp)))
        search.placeholderString = "Filter this folder"; search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 300).isActive = true
        navigation.addArrangedSubview(search)
        root.addArrangedSubview(navigation)
        table.addColumn("name", "Name", 360)
        table.addColumn("size", "Allocated size", 130)
        table.addColumn("kind", "Details", 470)
        table.delegate = self; table.dataSource = self; table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 28; table.target = self; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        let actions = NSStackView(); actions.spacing = 8
        actions.addArrangedSubview(button("Open Folder", #selector(openSelected)))
        actions.addArrangedSubview(button("Reveal in Finder", #selector(revealSelected)))
        actions.addArrangedSubview(button("Move to Trash…", #selector(trashSelected)))
        root.addArrangedSubview(actions)
        let footer = NSStackView(); footer.spacing = 10
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        footer.addArrangedSubview(progress); footer.addArrangedSubview(status)
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel)); cancelButton.isEnabled = false
        footer.addArrangedSubview(cancelButton); root.addArrangedSubview(footer)
        let note = NSTextField(wrappingLabelWithString: "Files stay on your Mac. Folder totals exclude symbolic links and other volumes; hard links count once. APFS shared blocks and unreadable folders can make totals differ from system storage. For protected folders, enable Disk Checker in System Preferences → Security & Privacy → Privacy → Full Disk Access, then reopen and rescan.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; root.addArrangedSubview(note)
        for view in [toolbar, title, metrics, chart, navigation, scroll, actions, footer, note] as [NSView] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        window.center(); window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
        #if CATALINA_UI_TESTS
        DispatchQueue.main.async { self.runCompatibilitySmokeTest() }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; controls.append(button); return button
    }
    private func setBusy(_ value: Bool, cancellable: Bool = true) {
        busy = value
        controls.forEach { $0.isEnabled = !value }
        search.isEnabled = !value
        cancelButton.isEnabled = value && cancellable
        if value { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }
    private func alert(_ message: String, detail: String = "") {
        let alert = NSAlert(); alert.messageText = message; alert.informativeText = detail
        alert.beginSheetModal(for: window)
    }
    private func confirm(_ message: String, detail: String, action: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = message; alert.informativeText = detail
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Move to Trash")
        alert.beginSheetModal(for: window) { response in if response == .alertSecondButtonReturn { action() } }
    }
    @objc private func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.prompt = "Scan Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.scan(url) }
        }
    }
    @objc private func quickScan(_ sender: NSPopUpButton) {
        let selected = sender.titleOfSelectedItem ?? ""
        sender.selectItem(at: 0)
        guard selected != "Quick Scan…" else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        scan(selected == "Home" ? home : selected == "Applications" ? URL(fileURLWithPath: "/Applications") : home.appendingPathComponent(selected))
    }
    @objc private func rescan() { if let root = result?.nodes.first?.url { scan(root) } }
    @objc private func cancel() { token?.cancel(); status.stringValue = "Cancelling…"; reportWindow?.setProgress("Cancelling…") }
    private func invalidateAI() { aiReport = nil; aiRoot = nil; reportWindow?.close(); reportWindow = nil }
    private func scan(_ url: URL) {
        guard !busy else { return }
        invalidateAI()
        let cancellation = ScanCancellation(); token = cancellation; setBusy(true)
        status.stringValue = "Scanning \(url.path)…"
        let scoped = url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
            let output = Result { try DiskScanner.scan(url, cancellation: cancellation) { count, path in
                DispatchQueue.main.async {
                    guard self.token === cancellation, !cancellation.isCancelled else { return }
                    self.status.stringValue = "\(count) files checked · \(path)"
                }
            } }
            DispatchQueue.main.async {
                if scoped { url.stopAccessingSecurityScopedResource() }
                self.token = nil; self.setBusy(false)
                switch output {
                case .success(let result):
                    self.result = result; self.current = 0; self.search.stringValue = ""; self.refresh()
                    self.status.stringValue = "\(result.fileCount) files checked · \(result.issues.count) skipped or unreadable locations"
                    if !result.issues.isEmpty { self.showDetails("Skipped or unreadable locations", result.issues.joined(separator: "\n")) }
                case .failure(let error):
                    if error is ScanCancelled { self.status.stringValue = "Scan cancelled. Previous completed results are preserved." }
                    else { self.status.stringValue = "Scan failed"; self.alert("Could not scan folder", detail: error.localizedDescription) }
                }
            }
        }
    }
    private func refresh() {
        guard let result = result else { rows = []; table.reloadData(); chart.nodes = []; return }
        let node = result.nodes[current]
        title.stringValue = node.url.path
        let values = try? node.url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        metrics.stringValue = "This folder: \(sizeText(node.bytes))     Volume available: \(sizeText(Int64(values?.volumeAvailableCapacity ?? 0)))     Volume capacity: \(sizeText(Int64(values?.volumeTotalCapacity ?? 0)))"
        rows = node.children.map { result.nodes[$0] }.filter { search.stringValue.isEmpty || $0.name.localizedCaseInsensitiveContains(search.stringValue) }
            .sorted { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }
        table.reloadData()
        chart.nodes = node.children.map { result.nodes[$0] }.sorted { $0.bytes > $1.bytes }
    }
    func controlTextDidChange(_ notification: Notification) { refresh() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let node = rows[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "size": value = sizeText(node.bytes)
        case "kind": value = node.isDirectory ? "Folder · \(node.children.count) immediate items · Double-click to explore" : node.url.pathExtension.uppercased() + " file"
        default: value = node.name
        }
        return tableView.label(value, column: tableColumn)
    }
    private var selected: ScanNode? { rows.indices.contains(table.selectedRow) ? rows[table.selectedRow] : nil }
    private func open(_ node: ScanNode) {
        guard !busy else { return }
        if node.isDirectory { current = node.id; search.stringValue = ""; refresh() }
        else { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
    }
    @objc private func openSelected() { if let node = selected { open(node) } }
    @objc private func goUp() {
        guard !busy, let parent = result?.nodes[current].parent else { return }
        current = parent; search.stringValue = ""; refresh()
    }
    @objc private func revealSelected() { if let selected = selected { NSWorkspace.shared.activateFileViewerSelecting([selected.url]) } }
    @objc private func trashSelected() {
        guard !busy, let selected = selected, let root = result?.nodes.first?.url else { return }
        guard TrashPolicy.allows(selected) else {
            alert("This item is not eligible for cleanup", detail: "Only items larger than 1 GB inside Desktop, Downloads, or Documents can be moved to Trash. The top-level folders cannot be deleted."); return
        }
        confirm("Move this item to Trash?", detail: "\(selected.url.path)\n\n\(sizeText(selected.bytes)) in the last scan. Moving a folder includes everything inside it. Restore items from Finder’s Trash. Space is reclaimed only after Trash is emptied.") {
            guard !self.busy, TrashPolicy.allows(selected) else { return }
            do {
                try FileManager.default.trashItem(at: selected.url, resultingItemURL: nil)
                self.result = nil; self.refresh(); self.scan(root)
            } catch { self.alert("Could not move item to Trash", detail: error.localizedDescription) }
        }
    }
    @objc private func checkAI() {
        guard !busy, let node = result?.nodes[current] else { return }
        invalidateAI(); aiRoot = node.url
        let cancellation = ScanCancellation(); token = cancellation; setBusy(true)
        let controller = ReportWindow(title: "AI Metadata", subtitle: node.url.path + "\nMetadata suggests AI involvement but can be edited or removed. No hints found does not mean human-made.")
        reportWindow = controller; controller.setWorking(true)
        controller.cancelAction = { [weak self] in self?.cancel() }
        controller.showWindow(nil)
        let scoped = node.url.startAccessingSecurityScopedResource()
        DispatchQueue.global(qos: .userInitiated).async {
            let report = AIMetadata.scan(node.url, cancellation: cancellation) { count, name in
                DispatchQueue.main.async {
                    guard self.token === cancellation, !cancellation.isCancelled else { return }
                    let message = "\(count) files checked · \(name)"
                    self.status.stringValue = message; controller.setProgress(message)
                }
            }
            DispatchQueue.main.async {
                if scoped { node.url.stopAccessingSecurityScopedResource() }
                self.aiReport = report; self.token = nil; self.setBusy(false)
                self.status.stringValue = report.cancelled ? "AI check cancelled — incomplete results" : "AI metadata check finished"
                controller.setReport(report)
            }
        }
    }
    @objc private func showAIResults() {
        guard !busy, aiReport != nil else { return }
        reportWindow?.showWindow(nil); reportWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc private func screenshots() {
        guard !busy else { return }
        cleanupWindow?.close(); cleanupWindow = nil
        setBusy(true, cancellable: false); status.stringValue = "Finding Desktop screenshots…"
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Result { try DesktopScreenshots.find() }
            DispatchQueue.main.async {
                self.setBusy(false); self.status.stringValue = "Screenshot review ready"
                switch found {
                case .failure(let error): self.alert("Could not inspect Desktop", detail: error.localizedDescription)
                case .success(let search):
                    let controller = ReportWindow(title: "Desktop Screenshots", subtitle: "Review detected screenshots directly on Desktop. Subfolders and symbolic links are excluded. Items move to Trash; space is reclaimed only after Trash is emptied.")
                    self.cleanupWindow = controller
                    controller.setScreenshots(search)
                    controller.cleanupAction = { [weak self, weak controller] in
                        guard let self = self, let controller = controller, !self.busy else { return }
                        let root = self.result?.nodes.first?.url
                        self.setBusy(true, cancellable: false); controller.setWorking(true, cancellable: false)
                        DispatchQueue.global(qos: .userInitiated).async {
                            let outcome = DesktopScreenshots.moveToTrash(search.items)
                            DispatchQueue.main.async {
                                self.setBusy(false); controller.setWorking(false)
                                controller.finishCleanup("Moved \(outcome.moved) of \(search.items.count) to Trash.\n" + outcome.issues.joined(separator: "\n"))
                                self.status.stringValue = "Screenshot cleanup finished"
                                if outcome.moved > 0 {
                                    self.invalidateAI()
                                    self.result = nil; self.refresh()
                                    if let root = root { self.scan(root) }
                                }
                            }
                        }
                    }
                    controller.showWindow(nil)
                }
            }
        }
    }
    private func showDetails(_ title: String, _ detail: String) {
        let controller = ReportWindow(title: title, subtitle: detail)
        reportWindow = controller; controller.showWindow(nil)
    }
}

private extension NSTableView {
    func addColumn(_ id: String, _ title: String, _ width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
        addTableColumn(column)
    }
    func label(_ value: String, column: NSTableColumn?) -> NSView {
        let id = column?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let label = (makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? NSTextField(labelWithString: "")
        label.identifier = id; label.stringValue = value; label.lineBreakMode = .byTruncatingMiddle; label.toolTip = value
        return label
    }
}

private final class StorageChart: NSView {
    var nodes: [ScanNode] = [] { didSet { needsDisplay = true } }
    var open: ((ScanNode) -> Void)?
    private var segments: [(NSRect, ScanNode)] = []
    override func draw(_ dirtyRect: NSRect) {
        segments = []
        let total = max(1, nodes.reduce(Int64(0)) { $0 + $1.bytes })
        let colors: [NSColor] = [.systemTeal, .systemBlue, .systemPurple, .systemOrange, .systemPink, .systemGreen, .systemIndigo]
        var x: CGFloat = 0
        for (index, node) in nodes.prefix(7).enumerated() {
            let width = bounds.width * CGFloat(node.bytes) / CGFloat(total)
            let rect = NSRect(x: x, y: 0, width: width, height: bounds.height)
            colors[index].setFill(); rect.fill(); segments.append((rect, node)); x += width
        }
        NSColor.separatorColor.setFill(); NSRect(x: x, y: 0, width: max(0, bounds.width - x), height: bounds.height).fill()
        toolTip = "Largest items: " + nodes.prefix(7).map { "\($0.name): \(sizeText($0.bytes))" }.joined(separator: ", ")
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let node = segments.first(where: { $0.0.contains(point) })?.1 { open?(node) }
    }
}

private final class ReportWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var cancelAction: (() -> Void)?
    var cleanupAction: (() -> Void)?
    private let table = NSTableView()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let details = NSTextView()
    private let filter = NSButton(checkboxWithTitle: "Show all inspection outcomes", target: nil, action: nil)
    private let actionButton = NSButton(title: "Cancel Check", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var report: AIReport?
    private var rows: [AIInspection] = []
    private var working = false
    private var cleaningScreenshots = false

    init(title: String, subtitle: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.minSize = NSSize(width: 760, height: 570); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20), root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20), root.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20)
        ])
        let heading = NSTextField(labelWithString: title); heading.font = .boldSystemFont(ofSize: 22); root.addArrangedSubview(heading)
        let explanation = NSTextField(wrappingLabelWithString: String(subtitle.prefix(700)))
        explanation.isSelectable = true; root.addArrangedSubview(explanation)
        root.addArrangedSubview(summary)
        filter.target = self; filter.action = #selector(toggleFilter); root.addArrangedSubview(filter)
        table.addColumn("name", "File", 260); table.addColumn("size", "Allocated size", 110); table.addColumn("status", "Result", 210); table.addColumn("tool", "Tool hint", 200)
        table.delegate = self; table.dataSource = self; table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 26
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder; root.addArrangedSubview(scroll); scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        let evidenceLabel = NSTextField(labelWithString: "Select a file to see its full path and metadata evidence:"); root.addArrangedSubview(evidenceLabel)
        let evidence = NSScrollView(); evidence.hasVerticalScroller = true; evidence.borderType = .bezelBorder
        details.isEditable = false; details.isSelectable = true; details.font = .systemFont(ofSize: 12)
        details.isVerticallyResizable = true; details.isHorizontallyResizable = false
        details.autoresizingMask = [.width]; details.textContainer?.widthTracksTextView = true
        details.string = subtitle; evidence.documentView = details; root.addArrangedSubview(evidence)
        evidence.heightAnchor.constraint(equalToConstant: 160).isActive = true
        let controls = NSStackView(); controls.spacing = 12
        let revealButton = NSButton(title: "Reveal in Finder", target: self, action: #selector(reveal)); controls.addArrangedSubview(revealButton)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false; controls.addArrangedSubview(spinner)
        actionButton.target = self; actionButton.action = #selector(action); actionButton.isHidden = true; controls.addArrangedSubview(actionButton)
        doneButton.target = self; doneButton.action = #selector(done); controls.addArrangedSubview(doneButton)
        root.addArrangedSubview(controls)
        for view in [explanation, summary, scroll, evidence, controls] as [NSView] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !working }
    func setWorking(_ value: Bool, cancellable: Bool = true) {
        working = value; doneButton.isEnabled = !value; filter.isEnabled = !value
        actionButton.isHidden = !value || !cancellable
        actionButton.title = "Cancel Check"
        if value { spinner.startAnimation(nil); summary.stringValue = "Working…" } else { spinner.stopAnimation(nil) }
    }
    func setProgress(_ value: String) { summary.stringValue = value }
    func setReport(_ value: AIReport) {
        setWorking(false); report = value
        let incomplete = value.cancelled || !value.issues.isEmpty || value.items.contains { $0.status == .unreadable }
        summary.stringValue = "\(value.cancelled ? "Cancelled" : "Check finished")\(incomplete ? " — incomplete results" : "") · \(value.inspected) images inspected · \(value.matches) with hints · \(value.skipped) skipped/unsupported · \(value.issues.count) location errors"
        details.string = "No hints found does not mean human-made. No C2PA validation. Non-PNG files over 8 MiB are reported as incomplete.\n\n" + value.issues.joined(separator: "\n")
        toggleFilter()
    }
    func setScreenshots(_ search: ScreenshotSearch) {
        cleaningScreenshots = true; filter.isHidden = true
        rows = search.items.map { AIInspection(url: $0.url, bytes: $0.bytes, status: .none, evidence: [], detail: "Detected Desktop screenshot. Review before moving to Trash.") }
        summary.stringValue = "\(rows.count) screenshots · \(sizeText(rows.reduce(0) { $0 + $1.bytes }))"
        details.string = search.issues.joined(separator: "\n")
        actionButton.title = "Move All to Trash…"; actionButton.isHidden = rows.isEmpty
        table.reloadData()
    }
    func finishCleanup(_ message: String) {
        cleaningScreenshots = false; rows = []; table.reloadData(); actionButton.isHidden = true
        summary.stringValue = "Cleanup finished"; details.string = message
    }
    @objc private func toggleFilter() {
        guard let report = report else { return }
        rows = report.items.filter { filter.state == .on || $0.status == .hints }; table.reloadData()
    }
    @objc private func action() {
        if working { cancelAction?(); return }
        guard cleaningScreenshots else { return }
        let alert = NSAlert(); alert.messageText = "Move all reviewed screenshots to Trash?"
        alert.informativeText = "\(rows.count) screenshots · \(sizeText(rows.reduce(0) { $0 + $1.bytes }))\nChanged files are skipped. You can restore items in Finder’s Trash."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Move All to Trash")
        alert.beginSheetModal(for: window!) { [weak self] response in if response == .alertSecondButtonReturn { self?.cleanupAction?() } }
    }
    @objc private func done() { if !working { close() } }
    @objc private func reveal() { if rows.indices.contains(table.selectedRow) { NSWorkspace.shared.activateFileViewerSelecting([rows[table.selectedRow].url]) } }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }; let item = rows[row]
        let value: String
        switch tableColumn?.identifier.rawValue {
        case "size": value = sizeText(item.bytes)
        case "status": value = cleaningScreenshots ? "Screenshot" : item.status.rawValue
        case "tool": value = Array(Set(item.evidence.map(\.tool))).sorted().joined(separator: ", ")
        default: value = item.url.lastPathComponent
        }
        return tableView.label(value, column: tableColumn)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard rows.indices.contains(table.selectedRow) else { return }
        let item = rows[table.selectedRow]
        details.string = item.url.path + "\n\n" + item.detail + "\n\n" + item.evidence.map { "\($0.tool)\n\($0.field): \($0.value)" }.joined(separator: "\n\n")
    }
}

#if CATALINA_UI_TESTS
// Compiled only into the disposable integration-test executable, never the app.
private extension CatalinaApp {
    func runCompatibilitySmokeTest() {
        precondition(CommandLine.arguments.count == 2, "Provide the synthetic fixture directory")
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        precondition(fixture.lastPathComponent == "ai-ui-fixtures")
        scan(fixture)
        waitForIdle {
            precondition(self.rows.count == 3 && self.result?.issues.isEmpty == true)
            self.search.stringValue = "Ordinary"
            self.refresh()
            precondition(self.rows.count == 1 && self.rows[0].name == "Ordinary image.png")
            self.search.stringValue = ""
            self.refresh()
            self.checkAI()
            precondition(self.busy)
            self.scan(fixture) // Must be ignored while inspecting metadata.
            self.waitForIdle {
                precondition(self.aiReport?.matches == 1 && self.aiReport?.inspected == 2)
                self.reportWindow!.verifyAndCapture(to: fixture.deletingLastPathComponent().appendingPathComponent("catalina-ai-ui.png"))
                self.scan(fixture)
                precondition(self.aiReport == nil && self.reportWindow == nil)
                self.waitForIdle {
                    self.window.contentView!.layoutSubtreeIfNeeded()
                    captureCompatibilityView(self.window.contentView!, to: fixture.deletingLastPathComponent().appendingPathComponent("catalina-main-ui.png"))
                    print("PASS: Catalina AppKit launch, storage scan, filtering, AI report, evidence, busy guard, and stale-result invalidation")
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
    func waitForIdle(_ attempts: Int = 400, completion: @escaping () -> Void) {
        precondition(attempts > 0, "Timed out waiting for Catalina operation")
        if !busy { completion(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.waitForIdle(attempts - 1, completion: completion) }
    }
}
private extension ReportWindow {
    func verifyAndCapture(to url: URL) {
        precondition(rows.count == 1 && rows[0].status == .hints)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        precondition(details.string.contains("ComfyUI") && details.string.contains("Software"))
        filter.state = .on; toggleFilter()
        precondition(rows.count == 3)
        window!.contentView!.layoutSubtreeIfNeeded()
        captureCompatibilityView(window!.contentView!, to: url)
    }
}
private func captureCompatibilityView(_ view: NSView, to url: URL) {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { preconditionFailure("No window bitmap") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let image = NSImage(size: view.bounds.size)
    image.lockFocus()
    NSColor.windowBackgroundColor.setFill()
    NSRect(origin: .zero, size: view.bounds.size).fill()
    bitmap.draw(in: NSRect(origin: .zero, size: view.bounds.size))
    image.unlockFocus()
    let composite = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try! composite.representation(using: .png, properties: [:])!.write(to: url)
}
#endif
