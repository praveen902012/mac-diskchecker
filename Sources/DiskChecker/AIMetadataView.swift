import SwiftUI
import AppKit

struct AIMetadataView: View {
    @ObservedObject var model: DiskModel
    @ViewState private var showAll = false

    private var items: [AIInspection] {
        (model.aiReport?.items ?? []).filter { showAll || $0.status == .hints }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI Metadata").font(.title2.bold())
            Text(model.aiPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Metadata suggests AI involvement but can be edited or removed. No hints found does not mean human-made.")
                .foregroundStyle(.secondary)
            if model.aiBusy {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(model.aiProgress).lineLimit(1).truncationMode(.middle)
                }
            }
            if let report = model.aiReport {
                Text(report.cancelled ? "Cancelled — incomplete results" : report.issues.isEmpty && !report.items.contains(where: { $0.status == .unreadable }) ? "Check complete" : "Check finished — some items could not be inspected")
                    .font(.headline)
                Text("\(report.inspected) images inspected · \(report.matches) with hints · \(report.skipped) skipped/unsupported · \(report.issues.count) location errors")
                    .font(.callout)
            }
            Toggle("Show all inspection outcomes", isOn: $showAll)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.url.lastPathComponent).fontWeight(.medium).lineLimit(1)
                        Spacer()
                        Text(sizeText(item.bytes)).monospacedDigit()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: { Image(systemName: "magnifyingglass") }
                            .help("Reveal in Finder").accessibilityLabel("Reveal \(item.url.lastPathComponent) in Finder")
                    }
                    Text(item.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(item.status.rawValue).font(.callout).foregroundStyle(item.status == .hints ? .orange : .secondary)
                    Text(item.detail).font(.caption)
                    if !item.evidence.isEmpty {
                        DisclosureGroup("Evidence · " + Array(Set(item.evidence.map(\.tool))).sorted().joined(separator: ", ")) {
                            ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, evidence in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(evidence.field).fontWeight(.medium)
                                    Text(evidence.value).textSelection(.enabled)
                                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                            }
                            Text("Long values are shortened to 4,096 characters.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }.frame(maxHeight: .infinity).overlay {
                if items.isEmpty && !model.aiBusy {
                    ContentUnavailableView("No \(showAll ? "inspection outcomes" : "AI metadata hints")", systemImage: "doc.text.magnifyingglass",
                        description: Text("Only supported embedded metadata is checked. This does not establish whether files are human-made."))
                }
            }
            if let report = model.aiReport, !report.issues.isEmpty {
                DisclosureGroup("Location errors (\(report.issues.count))") {
                    ScrollView { Text(report.issues.joined(separator: "\n")).font(.caption).textSelection(.enabled) }.frame(maxHeight: 80)
                }
            }
            Text("Local image metadata only · PNG, JPEG, HEIC, TIFF · No C2PA validation. Non-PNG files over 8 MiB are reported as incomplete.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                if model.aiBusy {
                    Button("Cancel Check") { model.cancelAI() }.keyboardShortcut(.cancelAction)
                } else {
                    Button("Done") { model.showAI = false }.keyboardShortcut(.defaultAction)
                }
            }
        }.padding(24).frame(width: 760, height: 620).interactiveDismissDisabled(model.aiBusy)
    }
}
