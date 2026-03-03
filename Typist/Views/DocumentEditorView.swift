//
//  DocumentEditorView.swift
//  Typist
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct DocumentEditorView: View {
    @Bindable var document: TypistDocument
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: Int = 0
    @State private var showingFontPicker = false
    @State private var showingFontManager = false
    @State private var showingProjectSettings = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var insertionRequest: String?

    private var fontPaths: [String] {
        FontManager.allFontPaths(for: document)
    }

    private var rootDir: String {
        ProjectFileManager.projectDirectory(for: document).path
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    EditorView(text: $document.content, insertionRequest: $insertionRequest)
                    Divider()
                    PreviewPane(source: document.content, fontPaths: fontPaths, rootDir: rootDir)
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

                    if selectedTab == 0 {
                        EditorView(text: $document.content, insertionRequest: $insertionRequest)
                    } else {
                        PreviewPane(source: document.content, fontPaths: fontPaths, rootDir: rootDir)
                    }
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Insert Image", systemImage: "photo")
                    }
                    Button {
                        showingFontManager = true
                    } label: {
                        Label("Fonts", systemImage: "textformat")
                    }
                    Button {
                        showingProjectSettings = true
                    } label: {
                        Label("Project Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
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
            ProjectSettingsSheet(document: document)
        }
        .onAppear {
            ProjectFileManager.ensureProjectStructure(for: document)
            FontManager.migrateToProject(for: document)
        }
        .onChange(of: document.content) {
            document.modifiedAt = Date()
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
