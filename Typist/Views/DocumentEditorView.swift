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
    /// Captures the PDF at the moment the user taps "Slideshow" so the
    /// fullScreenCover does not need to access compiler.pdfDocument in body.
    @State private var slideshowDocument: PDFDocument?

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
            onPhotoTapped: { showingPhotoPicker = true }
        )
        .background(Color.catppuccinBase)
        .ignoresSafeArea(edges: .bottom)
    }

    private var previewPane: some View {
        PreviewPane(compiler: compiler, source: entrySource, fontPaths: fontPaths, rootDir: rootDir, compileToken: compileToken)
            .background(Color.catppuccinMantle)
    }

    private func splitHandle(totalWidth: CGFloat) -> some View {
        Capsule()
            .fill(Color.catppuccinSubtext1)
            .frame(width: 4, height: 36)
            .frame(width: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("splitContainer"))
                    .onChanged { value in
                        let raw = value.location.x / totalWidth
                        withTransaction(Transaction(animation: nil)) {
                            editorFraction = min(0.8, max(0.2, raw))
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    withAnimation(.spring(duration: 0.3)) { editorFraction = 0.5 }
                }
            )
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
                slideshowDocument = compiler.pdfDocument
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
        .safeAreaInset(edge: .leading, spacing: 0) {
            if sizeClass == .regular && isSidebarVisible {
                Color.catppuccinBase.frame(width: 8)
            }
        }
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
        .sheet(item: $exporter.exportURL) { url in ActivityView(activityItems: [url]) }
        .fullScreenCover(isPresented: $showingSlideshow) {
            if let pdf = slideshowDocument {
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

    private func handleImageSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run { imageImportError = "Failed to load image data." }
                return
            }
            guard let uiImage = UIImage(data: data),
                  let jpegData = uiImage.jpegData(compressionQuality: 0.85) else {
                await MainActor.run { imageImportError = "Could not process image." }
                return
            }
            let fileName = "img-\(UUID().uuidString.prefix(8)).jpg"
            do {
                let relativePath = try ProjectFileManager.saveImage(data: jpegData, fileName: fileName, for: document)
                let reference = String(format: document.imageInsertionTemplate, relativePath)
                await MainActor.run {
                    insertionRequest = reference
                    selectedPhotoItems = []
                }
            } catch {
                await MainActor.run { imageImportError = error.localizedDescription }
            }
        }
    }
}
