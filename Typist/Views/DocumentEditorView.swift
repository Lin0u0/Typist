//
//  DocumentEditorView.swift
//  Typist
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private extension View {
    @ViewBuilder
    func navigationSubtitleCompat(_ subtitle: String) -> some View {
        if #available(iOS 26, *) {
            self.navigationSubtitle(subtitle)
        } else {
            self
        }
    }
}

struct DocumentEditorView: View {
    @Bindable var document: TypistDocument
    @Environment(\.horizontalSizeClass) private var sizeClass

    // MARK: - File-based editing state
    @State private var currentFileName: String = ""
    @State private var editorText: String = ""
    @State private var entrySource: String = ""
    @State private var compileToken: UUID = UUID()

    // MARK: - UI state
    @State private var selectedTab: Int = 0
    @State private var showingFontPicker = false
    @State private var showingFontManager = false
    @State private var showingProjectSettings = false
    @State private var showingPhotoPicker = false
    @State private var showingFileBrowser = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var insertionRequest: String?
    @State private var findRequested = false
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportURL: URL?

    private var fontPaths: [String] {
        FontManager.allFontPaths(for: document)
    }

    private var rootDir: String {
        ProjectFileManager.projectDirectory(for: document).path
    }

    private var isEditingEntryFile: Bool {
        currentFileName == document.entryFileName
    }

    private var editorPane: some View {
        EditorView(text: $editorText, insertionRequest: $insertionRequest, findRequested: $findRequested)
    }

    private var previewPane: some View {
        PreviewPane(source: entrySource, fontPaths: fontPaths, rootDir: rootDir, compileToken: compileToken)
    }

    @ViewBuilder
    private var contentLayout: some View {
        if sizeClass == .regular {
            HStack(spacing: 0) {
                editorPane
                Divider()
                previewPane
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
        }
    }

    private var toolbarMenu: some View {
        Menu {
            Button { showingFileBrowser = true } label: { Label("Project Files", systemImage: "folder") }
            Button { showingPhotoPicker = true } label: { Label("Insert Image", systemImage: "photo") }
            Button { showingFontManager = true } label: { Label("Fonts", systemImage: "textformat") }
            Button { showingProjectSettings = true } label: { Label("Project Settings", systemImage: "gearshape") }
            Divider()
            Button { findRequested = true } label: { Label("Find & Replace", systemImage: "magnifyingglass") }
            Divider()
            Button { exportSharePDF() } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
            Button { exportPrint() } label: { Label("Print", systemImage: "printer") }
            Button { exportTypSource() } label: { Label("Export .typ", systemImage: "doc.text") }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    var body: some View {
        contentLayout
        .navigationTitle(document.title)
        .navigationSubtitleCompat(currentFileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { toolbarMenu }
        }
        .photosPicker(isPresented: $showingPhotoPicker,
                      selection: $selectedPhotoItems,
                      maxSelectionCount: 1,
                      matching: .images)
        .onChange(of: selectedPhotoItems) { _, items in
            handleImageSelection(items)
        }
        .sheet(isPresented: $showingFontManager) {
            FontManagerSheet(document: document, showingFontPicker: $showingFontPicker)
                .fileImporter(
                    isPresented: $showingFontPicker,
                    allowedContentTypes: [.font],
                    allowsMultipleSelection: true
                ) { result in
                    handleFontImport(result)
                }
        }
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
        .onChange(of: editorText) { _, newText in
            saveCurrentFile(content: newText)
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Compiling…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(item: $exportURL) { url in
            ActivityView(activityItems: [url])
        }
        .alert("Export Error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: - File operations

    private func loadFile(named name: String) {
        let text = (try? ProjectFileManager.readTypFile(named: name, for: document)) ?? ""
        currentFileName = name
        editorText = text
        if name == document.entryFileName {
            entrySource = text
        }
    }

    /// Save current file content to disk.
    private func saveCurrentFile(content: String) {
        guard !currentFileName.isEmpty else { return }
        try? ProjectFileManager.writeTypFile(named: currentFileName, content: content, for: document)
        document.modifiedAt = Date()

        if isEditingEntryFile {
            entrySource = content
        } else {
            // Helper file changed — bump token to trigger recompile
            compileToken = UUID()
        }
    }

    /// Switch to editing a different file. Saves current file first.
    func openFile(named name: String) {
        saveCurrentFile(content: editorText)
        loadFile(named: name)
    }

    // MARK: - Export actions

    private func exportSharePDF() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            let result = await ExportManager.compilePDF(for: document)
            isExporting = false
            switch result {
            case .success(let data):
                do {
                    exportURL = try ExportManager.temporaryPDFURL(data: data, title: document.title)
                } catch {
                    exportError = error.localizedDescription
                }
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }

    private func exportPrint() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            let result = await ExportManager.compilePDF(for: document)
            isExporting = false
            switch result {
            case .success(let data):
                ExportManager.printPDF(data: data, jobName: document.title)
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }

    private func exportTypSource() {
        do {
            exportURL = try ExportManager.temporaryTypURL(for: document)
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Image handling

    private func handleImageSelection(_ items: [PhotosPickerItem]) {
        guard let item = items.first else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }

            // Convert through UIImage to ensure JPEG output (Typst doesn't support HEIC)
            guard let uiImage = UIImage(data: data),
                  let jpegData = uiImage.jpegData(compressionQuality: 0.85) else { return }

            let fileName = "img-\(UUID().uuidString.prefix(8)).jpg"
            guard let relativePath = try? ProjectFileManager.saveImage(
                data: jpegData, fileName: fileName, for: document
            ) else { return }

            let reference = String(format: document.imageInsertionTemplate, relativePath)
            await MainActor.run {
                insertionRequest = reference
                selectedPhotoItems = []
            }
        }
    }

    // MARK: - Font handling

    private func handleFontImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            if let name = try? FontManager.importFont(from: url, for: document),
               !document.fontFileNames.contains(name) {
                document.fontFileNames.append(name)
            }
        }
    }
}

// MARK: - Font Manager Sheet

private struct FontManagerSheet: View {
    @Bindable var document: TypistDocument
    @Binding var showingFontPicker: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Bundled Fonts") {
                    Label("Source Han Sans SC Regular", systemImage: "textformat")
                        .foregroundStyle(.secondary)
                }

                Section("Custom Fonts") {
                    if document.fontFileNames.isEmpty {
                        Text("No custom fonts added")
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(document.fontFileNames, id: \.self) { name in
                            Label(name, systemImage: "doc.text")
                        }
                        .onDelete { offsets in
                            let names = offsets.map { document.fontFileNames[$0] }
                            document.fontFileNames.remove(atOffsets: offsets)
                            for name in names {
                                FontManager.deleteFont(fileName: name, from: document)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fonts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingFontPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
