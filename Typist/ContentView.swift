//
//  ContentView.swift
//  Typist
//
//  Created by Lin Qidi on 2026/3/2.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedDocument: TypistDocument?

    var body: some View {
        NavigationSplitView {
            DocumentListView(selectedDocument: $selectedDocument)
        } detail: {
            if let document = selectedDocument {
                DocumentEditorView(document: document)
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text",
                    description: Text("Select a document from the list or create a new one.")
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TypistDocument.self, inMemory: true)
}
