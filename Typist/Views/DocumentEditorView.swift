//
//  DocumentEditorView.swift
//  Typist
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DocumentEditorView: View {
    @Bindable var document: TypistDocument
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: Int = 0
    @State private var showingFontPicker = false
    @State private var showingFontManager = false

    private var fontPaths: [String] {
        FontManager.allFontPaths(for: document)
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    EditorView(text: $document.content)
                    Divider()
                    PreviewPane(source: document.content, fontPaths: fontPaths)
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
                        EditorView(text: $document.content)
                    } else {
                        PreviewPane(source: document.content, fontPaths: fontPaths)
                    }
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFontManager = true
                } label: {
                    Image(systemName: "textformat")
                }
            }
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
        .onChange(of: document.content) {
            document.modifiedAt = Date()
        }
    }

    private func handleFontImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            if let name = try? FontManager.importFont(from: url),
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
                                FontManager.deleteFont(fileName: name)
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
