//
//  DocumentListView.swift
//  Typist
//

import SwiftUI
import SwiftData

struct DocumentListView: View {
    private enum SortField: String, CaseIterable, Identifiable {
        case title
        case modifiedAt
        case createdAt

        var id: String { rawValue }

        var label: String {
            switch self {
            case .title: L10n.tr("sort.field.title")
            case .modifiedAt: L10n.tr("sort.field.modified")
            case .createdAt: L10n.tr("sort.field.created")
            }
        }
    }

    private enum SortDirection: String, CaseIterable, Identifiable {
        case ascending
        case descending

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ascending: L10n.tr("sort.direction.ascending")
            case .descending: L10n.tr("sort.direction.descending")
            }
        }

        func orders(_ comparison: ComparisonResult) -> Bool {
            switch self {
            case .ascending:
                comparison == .orderedAscending
            case .descending:
                comparison == .orderedDescending
            }
        }
    }

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
    @State private var showingSettings = false
    @State private var projectActionError: String? = nil
    @State private var zipImportError: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var monitor = DirectoryMonitor()
    @State private var syncTask: Task<Void, Never>?
    @State private var sortField: SortField = .modifiedAt
    @State private var sortDirection: SortDirection = .descending
    @State private var showingSortPopover = false
    private let rowDateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    private var filteredDocuments: [TypistDocument] {
        guard !searchText.isEmpty else { return documents }
        return documents.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var sortedDocuments: [TypistDocument] {
        filteredDocuments.sorted(by: areDocumentsOrdered)
    }

    private var isShowingSearchEmptyState: Bool {
        !searchText.isEmpty && sortedDocuments.isEmpty
    }

    private var isShowingLibraryEmptyState: Bool {
        documents.isEmpty && searchText.isEmpty
    }

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        documentList
            .searchable(text: $searchText, prompt: "Search")
            .navigationTitle("Typist")
            .toolbar { if isIPad { iPadToolbar } else { iPhoneToolbar } }
            .overlay {
                if exporter.isExporting {
                    ZStack {
                        Color.catppuccinOverlayScrim.ignoresSafeArea()
                        ProgressView("Compiling…")
                            .padding()
                            .catppuccinFloatingSurface(cornerRadius: 12)
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
                        do {
                            let newFolderName = try ProjectFileManager.renameProjectDirectory(for: doc, to: newTitle)
                            doc.projectID = newFolderName
                            doc.title = newTitle
                            doc.modifiedAt = Date()
                        } catch {
                            projectActionError = error.localizedDescription
                        }
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
                        do {
                            try ProjectFileManager.deleteProjectDirectory(for: doc)
                            if selectedDocument == doc { selectedDocument = nil }
                            modelContext.delete(doc)
                        } catch {
                            projectActionError = error.localizedDescription
                        }
                        documentToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { documentToDelete = nil }
            } message: {
                if let doc = documentToDelete {
                    Text(L10n.deleteDocumentMessage(title: doc.title))
                }
            }
            .alert("Project Error", isPresented: Binding(
                get: { projectActionError != nil },
                set: { if !$0 { projectActionError = nil } }
            )) {
                Button("OK") { projectActionError = nil }
            } message: {
                Text(projectActionError ?? "")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(onImport: { url in importZip(from: url) })
                    .preferredColorScheme(themeManager.colorScheme)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { scheduleFilesystemSync(delay: .milliseconds(100)) }
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
            ForEach(sortedDocuments) { document in
                documentRow(document)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.catppuccinBase)
        .overlay {
            if isShowingLibraryEmptyState {
                libraryEmptyState
            } else if isShowingSearchEmptyState {
                searchEmptyState
            }
        }
        .task {
            ProjectFileManager.migrateLegacyStructure(documents: documents)
            syncWithFilesystem()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            monitor.onChange = { scheduleFilesystemSync() }
            monitor.start(url: docs)
        }
        .onDisappear {
            monitor.stop()
            syncTask?.cancel()
            syncTask = nil
        }
    }

    private func documentRow(_ document: TypistDocument) -> some View {
        let isSelected = selectedDocument === document

        return NavigationLink(value: document) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.catppuccinBlue : Color.primary)
                    .lineLimit(1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(L10n.tr("doc.time.created")): \(document.createdAt.formatted(rowDateFormat))")
                    Text("\(L10n.tr("doc.time.modified")): \(document.modifiedAt.formatted(rowDateFormat))")
                }
                .font(.caption)
                .foregroundStyle(Color.catppuccinSubtext1)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
        .listRowBackground(
            ZStack {
                Color.catppuccinElevated
                if isSelected {
                    Color.catppuccinBlue.opacity(0.16)
                }
            }
        )
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

    private var libraryEmptyState: some View {
        ContentUnavailableView {
            Label(L10n.tr("doc.list.empty.title"), systemImage: "folder")
        } description: {
            Text(L10n.tr("doc.list.empty.message"))
        }
    }

    private var searchEmptyState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private var toolbarButtonTint: Color {
        colorScheme == .dark ? .white : .black
    }

    @ToolbarContentBuilder
    private var iPadToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .scaleEffect(0.8)
            }
            .tint(toolbarButtonTint)
        }
        ToolbarItem(placement: .primaryAction) {
            sortMenu
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: addDocument) {
                Image(systemName: "folder.badge.plus")
                    .scaleEffect(0.8)
            }
            .tint(toolbarButtonTint)
        }
    }

    @ToolbarContentBuilder
    private var iPhoneToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            sortMenu
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .tint(toolbarButtonTint)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(action: addDocument) { Image(systemName: "folder.badge.plus") }
                .tint(toolbarButtonTint)
        }
    }

    private var sortMenu: some View {
        Button {
            showingSortPopover = true
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .scaleEffect(0.8)
        }
        .buttonStyle(.plain)
        .tint(toolbarButtonTint)
        .accessibilityLabel(L10n.tr("sort.menu.button"))
        .accessibilityValue("\(sortField.label), \(sortDirection.label)")
        .popover(
            isPresented: $showingSortPopover,
            attachmentAnchor: .point(.bottom),
            arrowEdge: .top
        ) {
            VStack(alignment: .leading, spacing: 14) {
                sortSection(title: L10n.tr("sort.menu.sort_by")) {
                    ForEach(SortField.allCases) { field in
                        sortSelectionRow(
                            title: field.label,
                            isSelected: field == sortField
                        ) {
                            sortField = field
                        }
                    }
                }

                Divider()

                sortSection(title: L10n.tr("sort.menu.order")) {
                    ForEach(SortDirection.allCases) { direction in
                        sortSelectionRow(
                            title: direction.label,
                            isSelected: direction == sortDirection
                        ) {
                            sortDirection = direction
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: 240)
            .catppuccinFloatingSurface(cornerRadius: 16)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func sortSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.catppuccinSubtext1)
                .textCase(.uppercase)

            content()
        }
    }

    private func sortSelectionRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showingSortPopover = false
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)

                Spacer(minLength: 12)

                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.primary)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func areDocumentsOrdered(_ lhs: TypistDocument, _ rhs: TypistDocument) -> Bool {
        let primaryComparison = compare(lhs, rhs, by: sortField)
        if primaryComparison != .orderedSame {
            return sortDirection.orders(primaryComparison)
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        let modifiedComparison = lhs.modifiedAt.compare(rhs.modifiedAt)
        if modifiedComparison != .orderedSame {
            return modifiedComparison == .orderedDescending
        }

        return lhs.createdAt > rhs.createdAt
    }

    private func compare(_ lhs: TypistDocument, _ rhs: TypistDocument, by field: SortField) -> ComparisonResult {
        switch field {
        case .title:
            lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        case .modifiedAt:
            lhs.modifiedAt.compare(rhs.modifiedAt)
        case .createdAt:
            lhs.createdAt.compare(rhs.createdAt)
        }
    }

    /// Coalesce bursty filesystem events into a single sync pass.
    private func scheduleFilesystemSync(delay: Duration = .milliseconds(300)) {
        syncTask?.cancel()
        syncTask = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                syncWithFilesystem()
            }
        }
    }

    private func syncWithFilesystem() {
        let existingFolders = ProjectFileManager.trackedFolderNames()

        for document in documents where !existingFolders.contains(document.projectID) {
            if selectedDocument == document {
                selectedDocument = nil
            }
            modelContext.delete(document)
        }

        let knownIDs = Set(documents.map { $0.projectID })
        let newFolders = ProjectFileManager.untrackedFolderNames(knownProjectIDs: knownIDs)
        for folderName in newFolders {
            let folderURL = ProjectFileManager.projectDirectory(folderName: folderName)
            let allFiles = ProjectFileManager.listAllFiles(in: folderURL)
            let doc = TypistDocument(title: folderName, content: "")
            doc.projectID = folderName
            configureImportedDocument(doc, relativePaths: allFiles)
            modelContext.insert(doc)
        }
    }

    private func configureImportedDocument(_ document: TypistDocument, relativePaths: [String]) {
        let typFiles = relativePaths.filter { $0.hasSuffix(".typ") }.sorted()
        let resolution = ProjectFileManager.resolveImportedEntryFile(from: typFiles)
        if let entryFile = resolution.entryFileName {
            document.entryFileName = entryFile
        }
        document.requiresInitialEntrySelection = resolution.requiresInitialSelection
        document.importEntryFileOptions = resolution.requiresInitialSelection ? typFiles : []

        let imageDirectoryOptions = ProjectFileManager.imageDirectoryCandidates(from: relativePaths)
        if ProjectFileManager.requiresImportDirectorySelection(imageDirectoryOptions) {
            document.importImageDirectoryOptions = imageDirectoryOptions
        } else {
            document.importImageDirectoryOptions = []
            if let autoImageDirectory = ProjectFileManager.defaultImportDirectory(from: imageDirectoryOptions) {
                document.imageDirectoryName = autoImageDirectory
            }
        }

        let fontDirectoryOptions = ProjectFileManager.fontDirectoryCandidates(from: relativePaths)
        if ProjectFileManager.requiresImportDirectorySelection(fontDirectoryOptions) {
            document.importFontDirectoryOptions = fontDirectoryOptions
        } else {
            document.importFontDirectoryOptions = []
            if let autoFontDirectory = ProjectFileManager.defaultImportDirectory(from: fontDirectoryOptions) {
                _ = ProjectFileManager.importFontFiles(from: autoFontDirectory, for: document)
            }
        }

        document.requiresImportConfiguration = document.requiresInitialEntrySelection
            || !document.importImageDirectoryOptions.isEmpty
            || !document.importFontDirectoryOptions.isEmpty
    }

    private func nextAvailableTitle() -> String {
        let titles = Set(documents.map { $0.title })
        let base = L10n.untitledBase
        if !titles.contains(base) { return base }
        var i = 1
        while titles.contains(L10n.untitled(number: i)) { i += 1 }
        return L10n.untitled(number: i)
    }

    private func addDocument() {
        let title = nextAvailableTitle()
        let doc = TypistDocument(title: title, content: "")
        doc.projectID = ProjectFileManager.uniqueFolderName(for: title)
        do {
            try ProjectFileManager.createInitialProject(for: doc)
            modelContext.insert(doc)
        } catch {
            try? ProjectFileManager.deleteProjectDirectory(for: doc)
            projectActionError = error.localizedDescription
            return
        }
        selectedDocument = doc
    }

    private func importZip(from url: URL) {
        let title = url.deletingPathExtension().lastPathComponent
        let doc = TypistDocument(title: title, content: "")
        doc.projectID = ProjectFileManager.uniqueFolderName(for: title)
        let destDir = ProjectFileManager.projectDirectory(for: doc)

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            try ProjectFileManager.createProjectRoot(for: doc)
            let extracted = try ZipImporter.extract(from: url, to: destDir)
            configureImportedDocument(doc, relativePaths: extracted)
            modelContext.insert(doc)
            selectedDocument = doc
        } catch {
            try? ProjectFileManager.deleteProjectDirectory(for: doc)
            zipImportError = error.localizedDescription
        }
    }
}
