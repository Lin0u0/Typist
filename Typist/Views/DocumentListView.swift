//
//  DocumentListView.swift
//  Typist
//

import SwiftUI
import SwiftData

struct DocumentListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TypistDocument.modifiedAt, order: .reverse) private var documents: [TypistDocument]
    @Binding var selectedDocument: TypistDocument?
    @State private var renamingDocument: TypistDocument?
    @State private var newTitle: String = ""

    var body: some View {
        List(selection: $selectedDocument) {
            ForEach(documents) { document in
                NavigationLink(value: document) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(document.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .contextMenu {
                    Button("Rename") {
                        renamingDocument = document
                        newTitle = document.title
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        if selectedDocument == document {
                            selectedDocument = nil
                        }
                        modelContext.delete(document)
                    }
                }
            }
            .onDelete(perform: deleteDocuments)
        }
        .navigationTitle("Typist")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: addDocument) {
                    Label("New Document", systemImage: "plus")
                }
            }
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
            Button("Cancel", role: .cancel) {
                renamingDocument = nil
            }
        }
    }

    private func addDocument() {
        let doc = TypistDocument(title: "Untitled", content: "")
        modelContext.insert(doc)
        selectedDocument = doc
    }

    private func deleteDocuments(offsets: IndexSet) {
        for index in offsets {
            let doc = documents[index]
            if selectedDocument == doc {
                selectedDocument = nil
            }
            modelContext.delete(doc)
        }
    }
}
