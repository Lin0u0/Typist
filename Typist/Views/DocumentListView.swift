//
//  DocumentListView.swift
//  Typist
//

import SwiftUI
import SwiftData

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(sort: \TypistDocument.createdAt, order: .reverse) private var documents: [TypistDocument]
    @Binding var selectedDocument: TypistDocument?
    @State private var renamingDocument: TypistDocument?
    @State private var newTitle: String = ""
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportURL: URL?
    @State private var documentToDelete: TypistDocument?
    @State private var searchText: String = ""

    private var filteredDocuments: [TypistDocument] {
        guard !searchText.isEmpty else { return documents }
        return documents.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        documentList
            .navigationTitle("Typist")
            .searchable(text: $searchText, prompt: "Search documents")
            .toolbar { toolbarContent }
            .toolbarBackground(Color.catppuccinMantle, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay { exportOverlay }
            .sheet(item: $exportURL) { ActivityView(activityItems: [$0]) }
            .alert("Export Error", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .alert("Rename Document", isPresented: Binding(
                get: { renamingDocument != nil },
                set: { if !$0 { renamingDocument = nil } }
            )) {
                TextField("Title", text: $newTitle)
                Button("Rename") {
                    renamingDocument?.title = newTitle
                    renamingDocument?.modifiedAt = Date()
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
    }

    // MARK: - Subviews

    private var documentList: some View {
        List(selection: $selectedDocument) {
            ForEach(filteredDocuments) { document in
                documentRow(document)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            documentToDelete = document
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.catppuccinMantle)
    }

    private func documentRow(_ document: TypistDocument) -> some View {
        NavigationLink(value: document) {
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(document.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.catppuccinSubtext1)
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.catppuccinSurface0)
        .contextMenu {
            Button("Rename") {
                renamingDocument = document
                newTitle = document.title
            }
            Divider()
            Button {
                exportSharePDF(for: document)
            } label: {
                Label("Share PDF", systemImage: "square.and.arrow.up")
            }
            Button {
                exportTypSource(for: document)
            } label: {
                Label("Export .typ", systemImage: "doc.text")
            }
            Divider()
            Button("Delete", role: .destructive) {
                if selectedDocument == document { selectedDocument = nil }
                ProjectFileManager.deleteProjectDirectory(for: document)
                modelContext.delete(document)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            Menu {
                Picker("Theme", selection: Binding(
                    get: { themeManager.themeID },
                    set: { id in
                        guard id != themeManager.themeID else { return }
                        withTransaction(Transaction(animation: nil)) {
                            themeManager.themeID = id
                        }
                    }
                )) {
                    Text("Auto").tag("system")
                    Text("Mocha · Dark").tag("mocha")
                    Text("Latte · Light").tag("latte")
                }
            } label: {
                Image(systemName: "paintpalette")
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            Button(action: addDocument) {
                Image(systemName: "plus")
            }
        }
    }
    
    @ViewBuilder
    private var exportOverlay: some View {
        if isExporting {
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("Compiling…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Export actions

    private func exportSharePDF(for document: TypistDocument) {
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

    private func exportTypSource(for document: TypistDocument) {
        do {
            exportURL = try ExportManager.temporaryTypURL(for: document)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func addDocument() {
        let doc = TypistDocument(title: "Untitled", content: "")
        modelContext.insert(doc)
        ProjectFileManager.ensureProjectStructure(for: doc)
        try? ProjectFileManager.writeTypFile(named: "main.typ", content: "", for: doc)
        selectedDocument = doc
    }

    private func deleteDocuments(offsets: IndexSet) {
        for index in offsets {
            let doc = documents[index]
            if selectedDocument == doc { selectedDocument = nil }
            ProjectFileManager.deleteProjectDirectory(for: doc)
            modelContext.delete(doc)
        }
    }
}
