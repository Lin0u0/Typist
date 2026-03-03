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
    @State private var themeManager = ThemeManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DocumentListView(selectedDocument: $selectedDocument, searchText: $searchText)
        } detail: {
            if let document = selectedDocument {
                DocumentEditorView(document: document, isSidebarVisible: columnVisibility != .detailOnly)
                    .id(document.persistentModelID)
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text",
                    description: Text("Select a document from the list or create a new one.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.catppuccinBase.ignoresSafeArea())
            }
        }
        .background(Color.catppuccinMantle.ignoresSafeArea())
        .tint(.catppuccinBlue)
        .preferredColorScheme(themeManager.colorScheme)
        .environment(themeManager)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TypistDocument.self, inMemory: true)
}
