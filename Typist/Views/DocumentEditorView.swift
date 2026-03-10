//
//  DocumentEditorView.swift
//  Typist
//

import SwiftUI
import SwiftData
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

private extension View {
    @ViewBuilder
    func navigationSubtitleCompat(_ subtitle: String) -> some View {
        if #available(iOS 26, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
    }

    @ViewBuilder
    func modify<T: View>(@ViewBuilder _ transform: (Self) -> T) -> some View {
        transform(self)
    }
}

private actor BackgroundDocumentFileWriter {
    func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct DocumentEditorView: View {
    private enum ImageImportSource {
        case photoItem(PhotosPickerItem)
        case rawData(Data, suggestedFileName: String?)
        case fileURL(URL)
        case remoteURL(URL, suggestedFileName: String?)
    }

    @Bindable var document: TypistDocument
    var isSidebarVisible: Bool = false
    @Environment(AppFontLibrary.self) private var appFontLibrary
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Compiler
    @State private var compiler = TypstCompiler()

    // MARK: - File-based editing state
    @State private var currentFileName: String = ""
    @State private var editorText: String = ""
    @State private var entrySource: String = ""
    @State private var compileToken: UUID = UUID()
    @State private var isLoadingFileContent = false
    @State private var lastPersistedText: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var backgroundFileWriter = BackgroundDocumentFileWriter()
    @State private var compileFontPaths: [String]

    // MARK: - UI state
    @State private var selectedTab: Int = 0
    @State private var showingSlideshow = false
    @State private var editorFraction: CGFloat = 0.5
    @State private var showingPhotoPicker = false
    @State private var showingFileBrowser = false
    @State private var showingProjectSettings = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var insertionRequest: String?
    @State private var findRequested = false
    @State private var exporter = ExportController()
    @State private var imageImportError: String?
    @State private var fileSaveError: String?
    @State private var previewActionError: String?
    @State private var isImageDropTarget = false
    @State private var pendingInsertionQueue: [String] = []
    @State private var imageImportToast: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var showingImportConfiguration = false
    @State private var showingZipExportWarning = false
    @State private var focusCoordinator = EditorFocusCoordinator()

    private var rootDir: String { ProjectFileManager.projectDirectory(for: document).path }
    private var isEditingEntryFile: Bool { currentFileName == document.entryFileName }

    init(document: TypistDocument, isSidebarVisible: Bool = false) {
        self.document = document
        self.isSidebarVisible = isSidebarVisible
        _compileFontPaths = State(initialValue: FontManager.allFontPaths(for: document))
    }

    // MARK: - Subviews

    private var editorPane: some View {
        EditorView(
            text: $editorText,
            insertionRequest: $insertionRequest,
            findRequested: $findRequested,
            focusCoordinator: focusCoordinator,
            theme: themeManager.currentTheme,
            onPhotoTapped: { showingPhotoPicker = true },
            onImagePasted: { pastedImageData in
                importImage(from: .rawData(pastedImageData, suggestedFileName: nil))
            },
            onRichPaste: { fragments in
                handleRichPaste(fragments)
            }
        )
        .onDrop(of: [UTType.image.identifier, UTType.fileURL.identifier],
                isTargeted: $isImageDropTarget,
                perform: handleImageDrop(providers:))
        .overlay {
            if isImageDropTarget {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.catppuccinBlue.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.catppuccinMantle)
        .ignoresSafeArea(edges: .bottom)
    }

    private var previewPane: some View {
        PreviewPane(
            compiler: compiler,
            source: entrySource,
            fontPaths: compileFontPaths,
            rootDir: rootDir,
            compileToken: compileToken,
            focusCoordinator: focusCoordinator
        )
            .background(Color.catppuccinMantle)
    }

    private func splitHandle(totalWidth: CGFloat) -> some View {
        let dragGesture = DragGesture(minimumDistance: 1, coordinateSpace: .named("splitContainer"))
            .onChanged { value in
                let raw = value.location.x / totalWidth
                withTransaction(Transaction(animation: nil)) {
                    editorFraction = min(0.8, max(0.2, raw))
                }
            }

        return Capsule()
            .fill(Color.catppuccinSubtext1)
            .frame(width: 2, height: 36)
            .overlay {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 28, height: 44)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            withAnimation(.spring(duration: 0.3)) { editorFraction = 0.5 }
                        }
                    )
            }
    }

    @ViewBuilder
    private var contentLayout: some View {
        if sizeClass == .regular {
            GeometryReader { geo in
                let total = geo.size.width
                HStack(spacing: 0) {
                    editorPane
                        .frame(width: total * editorFraction)
                    splitHandle(totalWidth: total)
                    previewPane
                }
                .coordinateSpace(name: "splitContainer")
            }
        } else {
            VStack(spacing: 0) {
                Picker("Mode", selection: $selectedTab) {
                    Text("Editor").tag(0)
                    Text("Preview").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if selectedTab == 0 { editorPane } else { previewPane }
            }
            .background(Color.catppuccinMantle)
        }
    }

    // MARK: - Toolbar

    /// Context-aware share: PDF on iPad/preview tab, .typ on editor tab.
    private var shareButtonAction: () -> Void {
        if sizeClass == .regular || selectedTab == 1 {
            return {
                flushPendingSave()
                exporter.exportPDF(for: document, cachedPDF: compiler.pdfDocument)
            }
        }
        return {
            flushPendingSave()
            exporter.exportTypSource(for: document, fileName: currentFileName)
        }
    }

    private var shareButtonLabel: String {
        if sizeClass == .regular || selectedTab == 1 { return "Share PDF" }
        return "Export .typ"
    }

    private var canTriggerPreviewActions: Bool {
        !entrySource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var toolbarMenu: some View {
        Menu {
            Section {
                Button { showingFileBrowser = true } label: {
                    Label("Project Files", systemImage: "folder")
                }
                Button { showingProjectSettings = true } label: {
                    Label("Project Settings", systemImage: "gearshape")
                }
                Button {
                    triggerZipExport()
                } label: {
                    Label("Export Project as Zip", systemImage: "archivebox")
                }
            }

            Section {
                Button { findRequested = true } label: {
                    Label(L10n.tr("action.find_replace"), systemImage: "magnifyingglass")
                }
            }

            Section {
                Button {
                    compilePreviewNow()
                } label: {
                    Label("Compile Now", systemImage: "play.circle")
                }
                .disabled(!canTriggerPreviewActions)

                Button {
                    clearCachesAndRecompile()
                } label: {
                    Label("Recompile", systemImage: "arrow.clockwise.circle")
                }
                .disabled(!canTriggerPreviewActions)

                Button {
                    showingSlideshow = true
                } label: {
                    Label("Slideshow", systemImage: "play.rectangle")
                }
                .disabled(!compiler.compiledOnce)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var editorChrome: some View {
        contentLayout
            .navigationTitle(document.title)
            .navigationSubtitleCompat(currentFileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.catppuccinMantle, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(Color.catppuccinMantle.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: shareButtonAction) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Color.catppuccinText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    toolbarMenu
                        .tint(Color.catppuccinText)
                }
            }
    }

    private var editorSheetsAndEvents: some View {
        editorChrome
            .photosPicker(isPresented: $showingPhotoPicker,
                          selection: $selectedPhotoItems,
                          maxSelectionCount: 1,
                          matching: .images)
            .onChange(of: selectedPhotoItems) { _, items in handleImageSelection(items) }
            .sheet(isPresented: $showingFileBrowser) {
                ProjectFileBrowserSheet(document: document, currentFileName: currentFileName, openFile: openFile)
            }
            .sheet(isPresented: $showingProjectSettings) {
                ProjectSettingsSheet(document: document, openFile: openFile)
            }
            .sheet(isPresented: $showingImportConfiguration) {
                InitialEntryFilePickerSheet(document: document) { selectedEntry, selectedImageDirectory, selectedFontDirectory in
                    if let selectedEntry {
                        document.entryFileName = selectedEntry
                    }
                    document.requiresInitialEntrySelection = false
                    if let selectedImageDirectory {
                        document.imageDirectoryName = selectedImageDirectory
                    } else {
                        document.imageDirectoryName = "images"
                        ProjectFileManager.ensureImageDirectory(for: document)
                    }
                    if let selectedFontDirectory {
                        _ = ProjectFileManager.importFontFiles(from: selectedFontDirectory, for: document)
                    } else {
                        ProjectFileManager.ensureFontsDirectory(for: document)
                    }
                    document.requiresImportConfiguration = false
                    document.importEntryFileOptions = []
                    document.importImageDirectoryOptions = []
                    document.importFontDirectoryOptions = []
                    showingImportConfiguration = false
                    loadFile(named: document.entryFileName)
                }
            }
            .onAppear {
                refreshCompileFontPaths()
                prepareDocumentForEditing()
            }
            .onDisappear {
                flushPendingSave()
                focusCoordinator.setResignSuppressed(false)
                compiler.cancel()
            }
            .onChange(of: editorText) { _, newText in
                guard !isLoadingFileContent else { return }
                handleEditorTextChange(newText)
            }
            .onChange(of: document.fontFileNames) { _, _ in
                handleCompileInputsChanged()
            }
            .onChange(of: appFontLibrary.items) { _, _ in
                handleCompileInputsChanged()
            }
            .onChange(of: insertionRequest) { _, newValue in
                if newValue == nil {
                    pumpPendingInsertionsIfNeeded()
                }
            }
    }

    private var editorOverlaysAndAlerts: some View {
        editorSheetsAndEvents
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
            .overlay(alignment: .bottom) {
                if let toast = imageImportToast {
                    Text(toast)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.catppuccinText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .catppuccinFloatingSurface(cornerRadius: 999)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(item: $exporter.exportURL) { url in ActivityView(activityItems: [url]) }
            .fullScreenCover(isPresented: $showingSlideshow) {
                if let pdf = compiler.pdfDocument {
                    SlideshowView(document: pdf)
                }
            }
            .alert("Export Error", isPresented: Binding(
                get: { exporter.exportError != nil },
                set: { if !$0 { exporter.exportError = nil } }
            )) {
                Button("OK") { exporter.exportError = nil }
            } message: {
                Text(exporter.exportError ?? "")
            }
            .alert(L10n.appFontsExportWarningTitle, isPresented: $showingZipExportWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    flushPendingSave()
                    exporter.exportZip(for: document)
                }
            } message: {
                Text(L10n.appFontsExportWarningMessage)
            }
            .alert("Image Import Error", isPresented: Binding(
                get: { imageImportError != nil },
                set: { if !$0 { imageImportError = nil } }
            )) {
                Button("OK") { imageImportError = nil }
            } message: {
                Text(imageImportError ?? "")
            }
            .alert("File Error", isPresented: Binding(
                get: { fileSaveError != nil },
                set: { if !$0 { fileSaveError = nil } }
            )) {
                Button("OK") { fileSaveError = nil }
            } message: {
                Text(fileSaveError ?? "")
            }
            .alert("Cache Error", isPresented: Binding(
                get: { previewActionError != nil },
                set: { if !$0 { previewActionError = nil } }
            )) {
                Button("OK") { previewActionError = nil }
            } message: {
                Text(previewActionError ?? "")
            }
    }

    // MARK: - Body

    var body: some View {
        editorOverlaysAndAlerts
    }

    // MARK: - File operations

    private func prepareDocumentForEditing() {
        ProjectFileManager.ensureProjectRoot(for: document)

        let typFiles = ProjectFileManager.listAllTypFiles(for: document)
        if document.requiresImportConfiguration || document.requiresInitialEntrySelection {
            let resolution = ProjectFileManager.resolveImportedEntryFile(from: typFiles)
            if let suggestedEntry = resolution.entryFileName {
                if !typFiles.contains(document.entryFileName) {
                    document.entryFileName = suggestedEntry
                }
                if resolution.requiresInitialSelection && document.importEntryFileOptions.isEmpty {
                    document.importEntryFileOptions = typFiles
                }
            }
            if !resolution.requiresInitialSelection {
                document.importEntryFileOptions = []
            }
            document.requiresInitialEntrySelection = resolution.requiresInitialSelection
            applyAutomaticImportDirectories()
            document.requiresImportConfiguration = document.requiresInitialEntrySelection
                || !document.importImageDirectoryOptions.isEmpty
                || !document.importFontDirectoryOptions.isEmpty
            if document.requiresImportConfiguration {
                showingImportConfiguration = true
                currentFileName = ""
                editorText = ""
                entrySource = ""
                return
            }
        }

        ProjectFileManager.migrateContentIfNeeded(for: document)
        loadFile(named: document.entryFileName)
    }

    private func loadFile(named name: String) {
        saveTask?.cancel()
        saveTask = nil
        let text = (try? ProjectFileManager.readTypFile(named: name, for: document)) ?? ""
        currentFileName = name
        isLoadingFileContent = true
        editorText = text
        isLoadingFileContent = false
        lastPersistedText = text
        if name == document.entryFileName {
            entrySource = text
        }
    }

    private func handleEditorTextChange(_ content: String) {
        guard !currentFileName.isEmpty else { return }
        if isEditingEntryFile {
            entrySource = content
        }
        scheduleSave(content: content, for: currentFileName)
    }

    private func scheduleSave(content: String, for fileName: String) {
        guard fileName == currentFileName else { return }
        guard content != lastPersistedText else {
            saveTask?.cancel()
            saveTask = nil
            return
        }

        let fileURL = ProjectFileManager.typFileURL(named: fileName, for: document)
        let shouldRefreshPreviewAfterSave = fileName != document.entryFileName

        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            do {
                try await backgroundFileWriter.write(content, to: fileURL)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self.currentFileName == fileName, self.editorText == content {
                        self.lastPersistedText = content
                        self.document.modifiedAt = Date()
                        if shouldRefreshPreviewAfterSave {
                            self.compileToken = UUID()
                        }
                    }
                    self.saveTask = nil
                }
            } catch {
                await MainActor.run {
                    self.fileSaveError = error.localizedDescription
                    self.saveTask = nil
                }
            }
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        persistCurrentFileImmediately(content: editorText)
    }

    private func persistCurrentFileImmediately(content: String) {
        guard !currentFileName.isEmpty else { return }
        guard content != lastPersistedText else { return }

        let shouldRefreshPreviewAfterSave = currentFileName != document.entryFileName
        let fileURL = ProjectFileManager.typFileURL(named: currentFileName, for: document)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            lastPersistedText = content
            document.modifiedAt = Date()
            if shouldRefreshPreviewAfterSave {
                compileToken = UUID()
            }
        } catch {
            fileSaveError = error.localizedDescription
        }
    }

    private func applyAutomaticImportDirectories() {
        if !ProjectFileManager.requiresImportDirectorySelection(document.importImageDirectoryOptions) {
            if let autoImageDirectory = ProjectFileManager.defaultImportDirectory(from: document.importImageDirectoryOptions) {
                document.imageDirectoryName = autoImageDirectory
            }
            document.importImageDirectoryOptions = []
        }

        if !ProjectFileManager.requiresImportDirectorySelection(document.importFontDirectoryOptions) {
            if let autoFontDirectory = ProjectFileManager.defaultImportDirectory(from: document.importFontDirectoryOptions) {
                _ = ProjectFileManager.importFontFiles(from: autoFontDirectory, for: document)
            }
            document.importFontDirectoryOptions = []
        }
    }

    func openFile(named name: String) {
        flushPendingSave()
        loadFile(named: name)
    }

    private func compilePreviewNow() {
        flushPendingSave()
        compiler.compileNow(source: entrySource, fontPaths: compileFontPaths, rootDir: rootDir)
    }

    private func clearCachesAndRecompile() {
        flushPendingSave()
        let source = entrySource
        let fontPaths = compileFontPaths
        let rootDir = rootDir

        compiler.clearPreview()

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PreviewPackageCacheStore().clearAll()
                }.value
                await MainActor.run {
                    compiler.compileNow(source: source, fontPaths: fontPaths, rootDir: rootDir)
                }
            } catch {
                await MainActor.run {
                    previewActionError = error.localizedDescription
                }
            }
        }
    }

    @discardableResult
    private func refreshCompileFontPaths() -> Bool {
        let latestPaths = FontManager.allFontPaths(for: document)
        guard latestPaths != compileFontPaths else { return false }
        compileFontPaths = latestPaths
        return true
    }

    private func handleCompileInputsChanged() {
        guard refreshCompileFontPaths() else { return }
        guard canTriggerPreviewActions else { return }
        compileToken = UUID()
    }

    private func triggerZipExport() {
        if appFontLibrary.isEmpty {
            flushPendingSave()
            exporter.exportZip(for: document)
        } else {
            showingZipExportWarning = true
        }
    }

    // MARK: - Image handling

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else {
                    Task { @MainActor in imageImportError = L10n.tr("error.image.load_data_failed") }
                    return
                }
                importImage(from: .rawData(data, suggestedFileName: provider.suggestedName))
            }
            return true
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let string = item as? String {
                url = URL(string: string)
            } else {
                url = nil
            }

            guard let fileURL = url else {
                Task { @MainActor in imageImportError = L10n.tr("error.image.load_data_failed") }
                return
            }
            importImage(from: .fileURL(fileURL))
        }
        return true
    }

    private func handleImageSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        importImage(from: .photoItem(item))
        selectedPhotoItems = []
    }

    private func importImage(from source: ImageImportSource) {
        Task {
            do {
                let result = try await importImageAsset(from: source)
                await MainActor.run {
                    enqueueInsertion(result.reference)
                    showImageImportToast(L10n.imageInserted(path: result.relativePath))
                }
            } catch {
                await MainActor.run {
                    imageImportError = error.localizedDescription
                }
            }
        }
    }

    private func handleRichPaste(_ fragments: [TypstTextView.PasteFragment]) {
        Task {
            var combinedInsertion = ""
            var firstError: String?
            var insertedImages: [String] = []

            for fragment in fragments {
                switch fragment {
                case .text(let text):
                    combinedInsertion.append(text)
                case .imageData(let data, let suggestedFileName):
                    do {
                        let result = try await importImageAsset(from: .rawData(data, suggestedFileName: suggestedFileName))
                        combinedInsertion.append(result.reference)
                        insertedImages.append(result.relativePath)
                    } catch {
                        if firstError == nil {
                            firstError = error.localizedDescription
                        }
                    }
                case .imageRemoteURL(let remoteURL, let suggestedFileName):
                    do {
                        let result = try await importImageAsset(from: .remoteURL(remoteURL, suggestedFileName: suggestedFileName))
                        combinedInsertion.append(result.reference)
                        insertedImages.append(result.relativePath)
                    } catch {
                        if firstError == nil {
                            firstError = error.localizedDescription
                        }
                    }
                }
            }

            await MainActor.run {
                if !combinedInsertion.isEmpty {
                    enqueueInsertion(combinedInsertion)
                }
                if let firstPath = insertedImages.first {
                    if insertedImages.count == 1 {
                        showImageImportToast(L10n.imageInserted(path: firstPath))
                    } else {
                        showImageImportToast(L10n.imagesInserted(count: insertedImages.count))
                    }
                }
                if let firstError {
                    imageImportError = firstError
                }
            }
        }
    }

    private func importImageAsset(from source: ImageImportSource) async throws -> (relativePath: String, reference: String) {
        let rawData = try await loadImageData(from: source)
        let normalized = try normalizeImageData(rawData)
        let fileName = makeUniqueImageFileName(ext: normalized.fileExtension, source: source)
        let relativePath = try ProjectFileManager.saveImage(data: normalized.data, fileName: fileName, for: document)
        let reference = normalizeTypstQuotes(String(format: document.imageInsertionTemplate, relativePath))
        return (relativePath, reference)
    }

    private func normalizeTypstQuotes(_ text: String) -> String {
        var normalized = text
        let quoteVariants = ["“", "”", "„", "‟", "＂", "«", "»", "「", "」", "『", "』", "〝", "〞", "‘", "’", "‚", "‛"]
        for q in quoteVariants {
            normalized = normalized.replacingOccurrences(of: q, with: "\"")
        }
        return normalized
    }

    private func loadImageData(from source: ImageImportSource) async throws -> Data {
        switch source {
        case .rawData(let data, _):
            return data
        case .photoItem(let item):
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "Typist.ImageImport", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("error.image.load_data_failed")])
            }
            return data
        case .fileURL(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                throw NSError(domain: "Typist.ImageImport", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("error.image.load_data_failed")])
            }
            return data
        case .remoteURL(let url, _):
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                throw NSError(domain: "Typist.ImageImport", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("error.image.load_data_failed")])
            }
            guard !data.isEmpty else {
                throw NSError(domain: "Typist.ImageImport", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("error.image.load_data_failed")])
            }
            return data
        }
    }

    private func normalizeImageData(_ data: Data) throws -> (data: Data, fileExtension: String) {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            throw NSError(domain: "Typist.ImageImport", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("error.image.process_failed")])
        }

        let hasAlpha: Bool = {
            switch cgImage.alphaInfo {
            case .first, .last, .premultipliedFirst, .premultipliedLast:
                return true
            default:
                return false
            }
        }()

        if hasAlpha {
            guard let pngData = uiImage.pngData() else {
                throw NSError(domain: "Typist.ImageImport", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("error.image.process_failed")])
            }
            return (pngData, "png")
        }

        guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "Typist.ImageImport", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("error.image.process_failed")])
        }
        return (jpegData, "jpg")
    }

    private func makeUniqueImageFileName(ext: String, source: ImageImportSource) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        let preferredBase = preferredImageBaseName(from: source)
        let base = preferredBase ?? "image-\(stamp)"
        let folder = ProjectFileManager.imagesDirectory(for: document)
        let fm = FileManager.default

        var candidate = "\(base).\(ext)"
        var index = 2
        while fm.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(index).\(ext)"
            index += 1
        }
        return candidate
    }

    private func preferredImageBaseName(from source: ImageImportSource) -> String? {
        let rawName: String?
        switch source {
        case .fileURL(let url):
            rawName = url.lastPathComponent
        case .rawData(_, let suggested):
            rawName = suggested
        case .remoteURL(let url, let suggested):
            rawName = suggested ?? url.lastPathComponent
        case .photoItem:
            rawName = nil
        }

        guard let rawName else { return nil }
        let base = URL(fileURLWithPath: rawName).deletingPathExtension().lastPathComponent
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let disallowed = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = trimmed.components(separatedBy: disallowed).joined(separator: "-")
        let collapsed = cleaned.replacingOccurrences(of: "  ", with: " ")
        let safe = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return safe.isEmpty ? nil : String(safe.prefix(80))
    }

    @MainActor
    private func enqueueInsertion(_ reference: String) {
        let normalizedReference = normalizeTypstQuotes(reference)
        if insertionRequest == nil {
            insertionRequest = normalizedReference
        } else {
            pendingInsertionQueue.append(normalizedReference)
        }
    }

    @MainActor
    private func pumpPendingInsertionsIfNeeded() {
        guard insertionRequest == nil, !pendingInsertionQueue.isEmpty else { return }
        insertionRequest = pendingInsertionQueue.removeFirst()
    }

    @MainActor
    private func showImageImportToast(_ message: String) {
        toastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            imageImportToast = message
        }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeInOut(duration: 0.18)) {
                imageImportToast = nil
            }
        }
    }
}
