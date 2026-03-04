//
//  DocumentListView.swift
//  Typist
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \TypistDocument.modifiedAt, order: .reverse) private var documents: [TypistDocument]
    @Binding var selectedDocument: TypistDocument?
    @Binding var searchText: String
    @State private var renamingDocument: TypistDocument?
    @State private var newTitle: String = ""
    @State private var exporter = ExportController()
    @State private var documentToDelete: TypistDocument?
    @State private var showingThemePicker = false
    @State private var showingZipImporter = false
    @State private var zipImportError: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var monitor = DirectoryMonitor()

    private var filteredDocuments: [TypistDocument] {
        guard !searchText.isEmpty else { return documents }
        return documents.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        documentList
            .searchable(text: $searchText, prompt: "Search documents")
            .navigationTitle("Typist")
            .toolbar { if isIPad { iPadToolbar } else { iPhoneToolbar } }
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay {
                if exporter.isExporting {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("Compiling…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .sheet(item: $exporter.exportURL) { ActivityView(activityItems: [$0]) }
            .alert("Export Error", isPresented: Binding(
                get: { exporter.exportError != nil },
                set: { if !$0 { exporter.exportError = nil } }
            )) {
                Button("OK") { exporter.exportError = nil }
            } message: {
                Text(exporter.exportError ?? "")
            }
            .alert("Rename Document", isPresented: Binding(
                get: { renamingDocument != nil },
                set: { if !$0 { renamingDocument = nil } }
            )) {
                TextField("Title", text: $newTitle)
                Button("Rename") {
                    if let doc = renamingDocument {
                        let newFolderName = ProjectFileManager.renameProjectDirectory(for: doc, to: newTitle)
                        doc.projectID = newFolderName
                        doc.title = newTitle
                        doc.modifiedAt = Date()
                    }
                    renamingDocument = nil
                }
                Button("Cancel", role: .cancel) { renamingDocument = nil }
            }
            .alert("Delete Document", isPresented: Binding(
                get: { documentToDelete != nil },
                set: { if !$0 { documentToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let doc = documentToDelete {
                        if selectedDocument == doc { selectedDocument = nil }
                        ProjectFileManager.deleteProjectDirectory(for: doc)
                        modelContext.delete(doc)
                        documentToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { documentToDelete = nil }
            } message: {
                if let doc = documentToDelete {
                    Text("\"\(doc.title)\" will be permanently deleted.")
                }
            }
            .fileImporter(isPresented: $showingZipImporter, allowedContentTypes: [.zip]) { result in
                switch result {
                case .success(let url): importZip(from: url)
                case .failure(let error): zipImportError = error.localizedDescription
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { syncWithFilesystem() }
            }
            .alert("Import Error", isPresented: Binding(
                get: { zipImportError != nil },
                set: { if !$0 { zipImportError = nil } }
            )) {
                Button("OK") { zipImportError = nil }
            } message: {
                Text(zipImportError ?? "")
            }
    }

    // MARK: - Subviews

    private var documentList: some View {
        List(selection: $selectedDocument) {
            ForEach(filteredDocuments) { document in
                documentRow(document)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.catppuccinMantle)
        .task {
            ProjectFileManager.migrateLegacyStructure(documents: documents)
            syncWithFilesystem()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            monitor.onChange = { syncWithFilesystem() }
            monitor.start(url: docs)
        }
        .onDisappear { monitor.stop() }
    }

    private func documentRow(_ document: TypistDocument) -> some View {
        NavigationLink(value: document) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(document.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.catppuccinSubtext1)
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.catppuccinSurface0)
        .contextMenu {
            Button {
                renamingDocument = document
                newTitle = document.title
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button {
                exporter.exportPDF(for: document)
            } label: {
                Label("Share PDF", systemImage: "square.and.arrow.up")
            }
            Button {
                exporter.exportTypSource(for: document, fileName: document.entryFileName)
            } label: {
                Label("Export .typ", systemImage: "doc.text")
            }
            Divider()
            Button(role: .destructive) {
                documentToDelete = document
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ToolbarContentBuilder
    private var iPadToolbar: some ToolbarContent {
        ToolbarItem() {
            Button {
                showingThemePicker = true
            } label: {
                Image(systemName: "paintpalette")
                    .scaleEffect(0.85)
            }
            .tint(themeManager.colorScheme == .light ? .black : .white)
            .popover(isPresented: $showingThemePicker) { themePickerPopover }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showingZipImporter = true } label: {
                Image(systemName: "square.and.arrow.down")
                    .scaleEffect(0.8)
            }
            .tint(themeManager.colorScheme == .light ? .black : .white)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: addDocument) {
                Image(systemName: "folder.badge.plus")
                    .scaleEffect(0.8)
            }
            .tint(themeManager.colorScheme == .light ? .black : .white)
        }
    }

    @ToolbarContentBuilder
    private var iPhoneToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Button {
                showingThemePicker = true
            } label: {
                Image(systemName: "paintpalette")
            }
            .tint(themeManager.colorScheme == .light ? .black : nil)
            .popover(isPresented: $showingThemePicker) { themePickerPopover }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button { showingZipImporter = true } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .tint(themeManager.colorScheme == .light ? .black : nil)
        }
        ToolbarItem(placement: .bottomBar) {
            Button(action: addDocument) { Image(systemName: "folder.badge.plus") }
                .tint(themeManager.colorScheme == .light ? .black : nil)
        }
    }

    private var themePickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([("system", "Auto"), ("mocha", "Mocha · Dark"), ("latte", "Latte · Light")], id: \.0) { id, label in
                Button {
                    guard id != themeManager.themeID else { return }
                    withTransaction(Transaction(animation: nil)) {
                        themeManager.themeID = id
                    }
                    showingThemePicker = false
                } label: {
                    HStack {
                        Text(label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if themeManager.themeID == id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if id != "latte" { Divider() }
            }
        }
        .frame(minWidth: 200)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Actions

    private func syncWithFilesystem() {
        let knownIDs = Set(documents.map { $0.projectID })
        let newFolders = ProjectFileManager.untrackedFolderNames(knownProjectIDs: knownIDs)
        for folderName in newFolders {
            let folderURL = ProjectFileManager.projectDirectory(folderName: folderName)
            let typFiles = (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path))?
                .filter { $0.hasSuffix(".typ") }.sorted() ?? []
            let entryFile = typFiles.first(where: { $0 == "main.typ" }) ?? typFiles.first ?? "main.typ"
            let doc = TypistDocument(title: folderName, content: "")
            doc.projectID = folderName
            doc.entryFileName = entryFile
            modelContext.insert(doc)
        }
    }

    private func nextAvailableTitle() -> String {
        let titles = Set(documents.map { $0.title })
        if !titles.contains("Untitled") { return "Untitled" }
        var i = 1
        while titles.contains("Untitled \(i)") { i += 1 }
        return "Untitled \(i)"
    }

    private func addDocument() {
        let title = nextAvailableTitle()
        let doc = TypistDocument(title: title, content: "")
        doc.projectID = ProjectFileManager.uniqueFolderName(for: title)
        modelContext.insert(doc)
        ProjectFileManager.ensureProjectStructure(for: doc)
        try? ProjectFileManager.writeTypFile(named: "main.typ", content: "", for: doc)
        selectedDocument = doc
    }

    private func importZip(from url: URL) {
        let title = url.deletingPathExtension().lastPathComponent
        let doc = TypistDocument(title: title, content: "")
        doc.projectID = ProjectFileManager.uniqueFolderName(for: title)
        modelContext.insert(doc)
        ProjectFileManager.ensureProjectStructure(for: doc)
        let destDir = ProjectFileManager.projectDirectory(for: doc)

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let extracted = try ZipImporter.extract(from: url, to: destDir)
            // Detect entry file: prefer main.typ, else first .typ file
            let typFiles = extracted.filter { $0.hasSuffix(".typ") && !$0.contains("/") }
            if let entry = typFiles.first(where: { $0 == "main.typ" }) ?? typFiles.first {
                doc.entryFileName = entry
            }
            selectedDocument = doc
        } catch {
            modelContext.delete(doc)
            ProjectFileManager.deleteProjectDirectory(for: doc)
            zipImportError = error.localizedDescription
        }
    }
}
