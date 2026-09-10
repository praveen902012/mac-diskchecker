import SwiftUI
import AppKit

func sizeText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

@MainActor
final class DiskModel: ObservableObject {
    @Published var screenshotBusy = false
    @Published var showScreenshots = false
    @Published var screenshots: [DesktopScreenshot] = []
    @Published var screenshotIssues: [String] = []
    @Published var screenshotReport: String?
    var busy: Bool { scanning || screenshotBusy }
    @Published var result: ScanResult?
    @Published var current = 0
    @Published var scanning = false
    @Published var status = "Choose a folder to discover what is taking up space."
    @Published var error: String?
    @Published var query = ""
    @Published var volumeTotal: Int64 = 0
    @Published var volumeFree: Int64 = 0
    private var cancellation: ScanCancellation?
    private var task: Task<Void, Never>?

    var node: ScanNode? { result?.nodes[current] }
    var children: [ScanNode] {
        guard let result, let node else { return [] }
        return node.children.map { result.nodes[$0] }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.bytes == $1.bytes ? $0.name < $1.name : $0.bytes > $1.bytes }
    }
    var breadcrumbs: [ScanNode] {
        guard let result else { return [] }
        var path: [ScanNode] = []
        var id: Int? = current
        while let i = id { path.append(result.nodes[i]); id = result.nodes[i].parent }
        return path.reversed()
    }
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan folder"
        if panel.runModal() == .OK, let url = panel.url { scan(url) }
    }
    func cancel() { cancellation?.cancel(); status = "Cancelling…" }
    func open(_ node: ScanNode) { current = node.id; query = "" }
    func reveal(_ node: ScanNode) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
    func reviewDesktopScreenshots() {
        guard !busy else { return }
        screenshots = []
        screenshotIssues = []
        screenshotReport = nil
        screenshotBusy = true
        showScreenshots = true
        Task {
            defer { screenshotBusy = false }
            do {
                let found = try await Task.detached(priority: .userInitiated) {
                    try DesktopScreenshots.find()
                }.value
                screenshots = found.items
                screenshotIssues = found.issues
            } catch {
                screenshotIssues = ["Could not read Desktop: \(error.localizedDescription)"]
            }
        }
    }
    func trashDesktopScreenshots() {
        guard !busy, !screenshots.isEmpty else { return }
        let reviewed = screenshots
        let root = result?.nodes.first?.url ?? DesktopScreenshots.desktop
        let previousFolder = node?.url
        screenshotBusy = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                DesktopScreenshots.moveToTrash(reviewed)
            }.value
            screenshotIssues.append(contentsOf: outcome.issues)
            screenshotReport = "Moved \(outcome.moved) of \(reviewed.count) screenshots to Trash."
            screenshots = []
            screenshotBusy = false
            if outcome.moved > 0 {
                result = nil
                current = 0
                scan(root, restoring: previousFolder)
            }
        }
    }
    func canTrash(_ node: ScanNode) -> Bool { TrashPolicy.allows(node) }
    func moveToTrash(_ item: ScanNode) {
        guard !busy, let result,
              result.nodes.indices.contains(item.id),
              result.nodes[item.id].url == item.url,
              canTrash(result.nodes[item.id]) else {
            error = "Only items larger than 1 GB inside Desktop, Downloads, or Documents can be moved to Trash. Rescan and try again."
            return
        }
        let root = result.nodes[0].url
        let previousFolder = node?.url
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            // Never keep actionable stale rows after a successful move, even if
            // the following refresh is cancelled or fails.
            self.result = nil
            current = 0
            scan(root, restoring: previousFolder)
        } catch {
            self.error = "Could not move \(item.name) to Trash: \(error.localizedDescription)"
        }
    }
    func scan(_ url: URL, restoring folder: URL? = nil) {
        guard !busy else { return }
        let token = ScanCancellation()
        cancellation = token
        scanning = true
        error = nil
        status = "Scanning \(url.path)…"
        let scoped = url.startAccessingSecurityScopedResource()
        task = Task {
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
                scanning = false
                cancellation = nil
            }
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try DiskScanner.scan(url, cancellation: token) { count, path in
                        Task { @MainActor [weak self] in
                            guard let self, self.scanning, self.cancellation === token, !token.isCancelled else { return }
                            self.status = "\(count.formatted()) files checked · \(path)"
                        }
                    }
                }.value
                result = output
                current = output.nodes.first(where: { $0.url == folder })?.id ?? 0
                query = ""
                let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                volumeTotal = Int64(values?.volumeTotalCapacity ?? 0)
                volumeFree = Int64(values?.volumeAvailableCapacity ?? 0)
                status = "\(output.fileCount.formatted()) files checked · \(output.issues.count) skipped or unreadable locations"
            } catch is CancellationError {
                status = "Scan cancelled. Any previous results are still available."
            } catch { self.error = error.localizedDescription; status = "Scan could not finish." }
        }
    }
}

@main
struct DiskCheckerApp: App {
    @StateObject private var model = DiskModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 880, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 780)
        .commands { CommandGroup(replacing: .newItem) {
            Button("Scan Folder…") { model.choose() }.keyboardShortcut("o").disabled(model.busy)
        } }
    }
}

struct ContentView: View {
    @ObservedObject var model: DiskModel
    @State private var showIssues = false
    @State private var pendingTrash: ScanNode?
    @State private var showTrashConfirmation = false
    private let colors: [Color] = [.teal, .blue, .indigo, .purple, .pink, .orange, .mint, .cyan]
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Disk Checker", systemImage: "internaldrive.fill")
                    .font(.title2.bold())
                Text("A clearer view of your storage.").foregroundStyle(.secondary)
                Button { model.choose() } label: {
                    Label("Scan a folder", systemImage: "folder.badge.plus").frame(maxWidth: .infinity)
                }.controlSize(.large).buttonStyle(.borderedProminent).tint(.teal).disabled(model.busy)
                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK SCAN").font(.caption.bold()).foregroundStyle(.secondary)
                    quick("Home folder", icon: "house", url: FileManager.default.homeDirectoryForCurrentUser)
                    quick("Desktop", icon: "desktopcomputer", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
                    quick("Documents", icon: "doc.text", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"))
                    quick("Downloads", icon: "arrow.down.circle", url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                    quick("Applications", icon: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications"))
                }
                Button { model.reviewDesktopScreenshots() } label: {
                    Label("Delete Desktop Screenshots…", systemImage: "photo.on.rectangle")
                }.disabled(model.busy)
                Spacer()
                Label("Private by design", systemImage: "lock.shield").font(.headline)
                Text("Files stay on your Mac. Review large items or Desktop screenshots before moving them to Trash.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("For protected folders, allow Disk Checker in System Settings → Privacy & Security → Full Disk Access, then reopen the app and rescan.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            }.frame(width: 220).frame(maxHeight: .infinity).background(.thinMaterial)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.node?.name ?? "Make room for what matters.").font(.largeTitle.bold())
                        Text(model.node?.url.path ?? "See the biggest files and folders, all in one place.")
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if let root = model.result?.nodes.first {
                        Button { model.scan(root.url) } label: { Image(systemName: "arrow.clockwise") }
                            .help("Rescan folder").disabled(model.busy)
                    }
                }
                if model.scanning {
                    HStack { ProgressView().controlSize(.small); Text(model.status).lineLimit(1).truncationMode(.middle); Spacer(); Button("Cancel") { model.cancel() } }
                        .padding(12).background(.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if let node = model.node {
                    HStack(spacing: 16) {
                        metric("This folder", value: sizeText(node.bytes), subtitle: "Allocated file storage")
                        metric("Volume used", value: sizeText(max(0, model.volumeTotal - model.volumeFree)), subtitle: "Of \(sizeText(model.volumeTotal)) capacity")
                        metric("Volume available", value: sizeText(model.volumeFree), subtitle: "Reported by the filesystem")
                    }
                    chart
                    HStack {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(model.breadcrumbs) { crumb in
                                    Button(crumb.name) { model.open(crumb) }.buttonStyle(.link)
                                    if crumb.id != model.current { Image(systemName: "chevron.right").font(.caption2) }
                                }
                            }
                        }
                        TextField("Filter this folder", text: $model.query).textFieldStyle(.roundedBorder).frame(width: 180)
                    }
                    List(model.children) { child in
                        HStack(spacing: 12) {
                            Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(child.isDirectory ? .teal : .secondary).font(.title2).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(child.name).fontWeight(.medium).lineLimit(1)
                                Text(explanation(child)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(sizeText(child.bytes)).monospacedDigit().fontWeight(.semibold)
                                ProgressView(value: Double(child.bytes), total: Double(max(1, node.bytes))).tint(.teal).frame(width: 100)
                            }
                            Button { model.reveal(child) } label: { Image(systemName: "magnifyingglass") }.help("Reveal in Finder")
                            if model.canTrash(child) {
                                Button(role: .destructive) {
                                    pendingTrash = child
                                    showTrashConfirmation = true
                                } label: { Label("Delete", systemImage: "trash") }
                                .help("Move to Trash")
                                .disabled(model.busy)
                            }
                            if child.isDirectory {
                                Button { model.open(child) } label: { Image(systemName: "chevron.right") }.help("Explore folder")
                            } else { Color.clear.frame(width: 24, height: 1) }
                        }.padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if child.isDirectory { model.open(child) } else { model.reveal(child) } }
                        .contextMenu { Button("Reveal in Finder") { model.reveal(child) } }
                    }.listStyle(.inset).overlay {
                        if model.children.isEmpty { ContentUnavailableView(model.query.isEmpty ? "No files to display" : "No matches", systemImage: "folder") }
                    }
                    HStack {
                        Text(model.scanning ? "Showing previous scan" : model.status).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if !(model.result?.issues.isEmpty ?? true) { Button("View skipped locations") { showIssues = true }.font(.caption) }
                    }
                    Text("Folder totals exclude symbolic links and other volumes. Hard links count once. APFS shared blocks, snapshots, and unreadable folders can make totals differ from system storage.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !model.scanning {
                    Spacer()
                    ContentUnavailableView {
                        Label("Find your biggest space consumers", systemImage: "chart.bar.xaxis")
                    } description: {
                        Text("Choose a folder or start with your Home folder. Explore the results by size and reveal anything in Finder.")
                    } actions: {
                        Button("Scan Home Folder") { model.scan(FileManager.default.homeDirectoryForCurrentUser) }.buttonStyle(.borderedProminent).tint(.teal)
                    }
                    Spacer()
                } else { Spacer() }
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Move this item to Trash?", isPresented: $showTrashConfirmation, presenting: pendingTrash) { item in
            Button("Cancel", role: .cancel) { pendingTrash = nil }
            Button("Move to Trash", role: .destructive) {
                model.moveToTrash(item)
                pendingTrash = nil
            }
        } message: { item in
            Text("\(item.url.path)\n\n\(sizeText(item.bytes)) in the last scan.\(item.isDirectory ? " This moves the folder and everything inside it." : "") You can restore it from Finder’s Trash. Space is reclaimed only after the Trash is emptied.")
        }
        .sheet(isPresented: $model.showScreenshots) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Delete Desktop Screenshots").font(.title2.bold())
                Text("Review all detected screenshots directly on your Desktop. Screenshots of any size are included. Subfolders are excluded.")
                    .foregroundStyle(.secondary)
                if model.screenshotBusy {
                    HStack { ProgressView().controlSize(.small); Text("Working…") }
                } else if let report = model.screenshotReport {
                    Text(report).font(.headline)
                } else {
                    Text("\(model.screenshots.count) screenshots · \(sizeText(model.screenshots.reduce(0) { $0 + $1.bytes }))")
                        .font(.headline)
                }
                if !model.screenshots.isEmpty {
                    List(model.screenshots) { item in
                        HStack {
                            Text(item.url.lastPathComponent).lineLimit(1).help(item.url.path)
                            Spacer()
                            Text(sizeText(item.bytes)).foregroundStyle(.secondary)
                            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                                Image(systemName: "magnifyingglass")
                            }.help("Reveal in Finder")
                        }
                    }
                } else if !model.screenshotBusy && model.screenshotReport == nil {
                    Text(model.screenshotIssues.isEmpty ? "No Desktop screenshots found." : "No screenshots available for cleanup.")
                }
                if !model.screenshotIssues.isEmpty {
                    Text("Skipped or unreadable items").font(.headline)
                    ScrollView {
                        Text(model.screenshotIssues.joined(separator: "\n")).font(.caption).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }
                Spacer(minLength: 0)
                Text("Detected using macOS screenshot metadata or standard Screenshot / Screen Shot date-and-time filenames. Review the list before continuing.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Items go to Trash and can be restored in Finder. Space is reclaimed only after you empty the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(model.screenshotReport == nil ? "Cancel" : "Done") { model.showScreenshots = false }
                        .keyboardShortcut(.cancelAction).disabled(model.screenshotBusy)
                    if model.screenshotReport == nil {
                        Button("Move All to Trash", role: .destructive) { model.trashDesktopScreenshots() }
                            .disabled(model.busy || model.screenshots.isEmpty)
                    }
                }
            }.padding(24).frame(width: 680, height: 520)
                .interactiveDismissDisabled(model.screenshotBusy)
        }
        .sheet(isPresented: $showIssues) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Skipped or unreadable locations").font(.title2.bold())
                Text("These locations are missing from the totals. Permissions or files changing during a scan can cause this.").foregroundStyle(.secondary)
                ScrollView { Text(model.result?.issues.joined(separator: "\n\n") ?? "").font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack { Spacer(); Button("Done") { showIssues = false }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 680, height: 440)
        }
    }
    private func quick(_ name: String, icon: String, url: URL) -> some View {
        Button { model.scan(url) } label: { Label(name, systemImage: icon) }.buttonStyle(.plain).disabled(model.busy)
    }
    private func metric(_ title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
    private var chart: some View {
        let children = (model.node?.children ?? []).compactMap { model.result?.nodes[$0] }.sorted { $0.bytes > $1.bytes }
        let top = Array(children.prefix(7))
        let remainder = children.dropFirst(7).reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Where the space goes").font(.headline)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, node in
                        Rectangle().fill(colors[index]).frame(width: geometry.size.width * CGFloat(node.bytes) / CGFloat(max(1, model.node?.bytes ?? 0)))
                            .help("\(node.name): \(sizeText(node.bytes))")
                            .onTapGesture { if node.isDirectory { model.open(node) } else { model.reveal(node) } }
                    }
                    if remainder > 0 { Rectangle().fill(.gray).help("Other: \(sizeText(remainder))") }
                }.clipShape(RoundedRectangle(cornerRadius: 7))
            }.frame(height: 28)
            ViewThatFits {
                HStack(spacing: 12) { legend(top) }
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 12) { legend(top) } }
            }
        }
    }
    private func legend(_ nodes: [ScanNode]) -> some View {
        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
            HStack(spacing: 4) { Circle().fill(colors[index]).frame(width: 7, height: 7); Text(node.name).lineLimit(1) }.font(.caption)
        }
    }
    private func explanation(_ node: ScanNode) -> String {
        switch node.name.lowercased() {
        case "caches": return "Cached app data. Manage through the owning app when possible."
        case "downloads": return "Downloaded files and installers. Review what you still need."
        case "applications": return "Installed apps and their bundled resources."
        case "library": return "App support, caches, settings, and other app data."
        case "developer", "deriveddata": return "Developer tools and build data. Review using your development tools."
        case "node_modules": return "JavaScript dependencies for this project."
        case "pictures", "photos library.photoslibrary": return "Photos and image libraries. Manage library contents in Photos."
        case "movies": return "Videos, recordings, and movie libraries."
        case "mobilesync": return "May contain local iPhone or iPad backups. Review backups in Finder."
        case ".trash": return "Items already in the Trash. Review them in Finder."
        default: return node.isDirectory ? "\(node.children.count.formatted()) immediate items · Double-click to explore" : node.url.pathExtension.isEmpty ? "File" : "\(node.url.pathExtension.uppercased()) file"
        }
    }
}
