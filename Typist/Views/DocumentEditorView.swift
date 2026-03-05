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

struct DocumentEditorView: View {
    private enum ImageImportSource {
        case photoItem(PhotosPickerItem)
        case rawData(Data, suggestedFileName: String?)
        case fileURL(URL)
        case remoteURL(URL, suggestedFileName: String?)
    }

    @Bindable var document: TypistDocument
    var isSidebarVisible: Bool = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(ThemeManager.self) private var themeManager

    // MARK: - Compiler
    @State private var compiler = TypstCompiler()

    // MARK: - File-based editing state
    @State private var currentFileName: String = ""
    @State private var editorText: String = ""
    @State private var entrySource: String = ""
    @State private var compileToken: UUID = UUID()

    // MARK: - UI state
    @State private var selectedTab: Int = 0
    @State private var showingSlideshow = false
    @State private var editorFraction: CGFloat = 0.5
    @State private var showingProjectSettings = false
    @State private var showingPhotoPicker = false
    @State private var showingFileBrowser = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var insertionRequest: String?
    @State private var findRequested = false
    @State private var exporter = ExportController()
    @State private var imageImportError: String?
    @State private var isImageDropTarget = false
    @State private var pendingInsertionQueue: [String] = []
    @State private var imageImportToast: String?
    @State private var toastDismissTask: Task<Void, Never>?

    private var fontPaths: [String] { FontManager.allFontPaths(for: document) }
    private var rootDir: String { ProjectFileManager.projectDirectory(for: document).path }
    private var isEditingEntryFile: Bool { currentFileName == document.entryFileName }

    // MARK: - Subviews

    private var editorPane: some View {
        EditorView(
            text: $editorText,
            insertionRequest: $insertionRequest,
            findRequested: $findRequested,
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
                    .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.catppuccinMantle)
        .ignoresSafeArea(edges: .bottom)
    }

    private var previewPane: some View {
        PreviewPane(compiler: compiler, source: entrySource, fontPaths: fontPaths, rootDir: rootDir, compileToken: compileToken)
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
        if sizeClass == .regular || selectedTab == 1 { return { exporter.exportPDF(for: document, cachedPDF: compiler.pdfDocument) } }
        return { exporter.exportTypSource(for: document, fileName: currentFileName) }
    }

    private var shareButtonLabel: String {
        if sizeClass == .regular || selectedTab == 1 { return "Share PDF" }
        return "Export .typ"
    }

    private var toolbarMenu: some View {
        Menu {
            Button { showingFileBrowser = true } label: { Label("Project Files", systemImage: "folder") }
            Button { showingProjectSettings = true } label: { Label("Project Settings", systemImage: "gearshape") }
            Divider()
            Button { findRequested = true } label: { Label("Find & Replace", systemImage: "magnifyingglass") }
            Divider()
            Button {
                exporter.exportZip(for: document)
            } label: {
                Label("Export Project as Zip", systemImage: "archivebox")
            }
            Divider()
            Button {
                showingSlideshow = true
            } label: {
                Label("Slideshow", systemImage: "play.rectangle")
            }
            .disabled(!compiler.compiledOnce)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Body

    var body: some View {
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
                .tint(themeManager.colorScheme == .light ? .black : .white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                toolbarMenu
                    .tint(themeManager.colorScheme == .light ? .black : .white)
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker,
                      selection: $selectedPhotoItems,
                      maxSelectionCount: 1,
                      matching: .images)
        .onChange(of: selectedPhotoItems) { _, items in handleImageSelection(items) }
        .sheet(isPresented: $showingProjectSettings) {
            ProjectSettingsSheet(document: document, openFile: openFile)
        }
        .sheet(isPresented: $showingFileBrowser) {
            ProjectFileBrowserSheet(document: document, currentFileName: currentFileName, openFile: openFile)
        }
        .onAppear {
            ProjectFileManager.ensureProjectStructure(for: document)
            ProjectFileManager.migrateContentIfNeeded(for: document)
            loadFile(named: document.entryFileName)
        }
        .onDisappear { compiler.cancel() }
        .onChange(of: editorText) { _, newText in saveCurrentFile(content: newText) }
        .onChange(of: insertionRequest) { _, newValue in
            if newValue == nil {
                pumpPendingInsertionsIfNeeded()
            }
        }
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
        .overlay(alignment: .bottom) {
            if let toast = imageImportToast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.75), in: Capsule())
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
        .alert("Image Import Error", isPresented: Binding(
            get: { imageImportError != nil },
            set: { if !$0 { imageImportError = nil } }
        )) {
            Button("OK") { imageImportError = nil }
        } message: {
            Text(imageImportError ?? "")
        }
    }

    // MARK: - File operations

    private func loadFile(named name: String) {
        let text = (try? ProjectFileManager.readTypFile(named: name, for: document)) ?? ""
        currentFileName = name
        editorText = text
        if name == document.entryFileName { entrySource = text }
    }

    private func saveCurrentFile(content: String) {
        guard !currentFileName.isEmpty else { return }
        try? ProjectFileManager.writeTypFile(named: currentFileName, content: content, for: document)
        document.modifiedAt = Date()
        if isEditingEntryFile {
            entrySource = content
        } else {
            compileToken = UUID()
        }
    }

    func openFile(named name: String) {
        saveCurrentFile(content: editorText)
        loadFile(named: name)
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
                    showImageImportToast("Inserted \(result.relativePath)")
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
                        showImageImportToast("Inserted \(firstPath)")
                    } else {
                        showImageImportToast("Inserted \(insertedImages.count) images")
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
