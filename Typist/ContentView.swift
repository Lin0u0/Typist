//
//  ContentView.swift
//  Typist
//
//  Created by Lin Qidi on 2026/3/2.
//

import SwiftUI
import SwiftData
import UIKit

/// Sets the title of the UIWindowScene that contains this view.
/// This controls the name shown in the iPadOS app switcher and window labels.
private struct SceneTitleSetter: UIViewRepresentable {
    let title: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            uiView.window?.windowScene?.title = title
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDocument: TypistDocument?
    @State private var themeManager = ThemeManager()
    @State private var appAppearanceManager = AppAppearanceManager()
    @State private var appFontLibrary = AppFontLibrary()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText: String = ""
    @State private var didSeedUITestDocument = false

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
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            }
        }
        .background(SceneTitleSetter(title: selectedDocument?.title ?? L10n.appName))
        .preferredColorScheme(appAppearanceManager.colorScheme)
        .environment(appAppearanceManager)
        .environment(themeManager)
        .environment(appFontLibrary)
        .task {
            seedUITestDocumentIfNeeded()
        }
    }

    private var shouldSeedUITestDocument: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("UITEST_SEED_SAMPLE_DOCUMENT")
            || processInfo.environment["UITEST_SEED_SAMPLE_DOCUMENT"] == "1"
    }

    @MainActor
    private func seedUITestDocumentIfNeeded() {
        guard shouldSeedUITestDocument, !didSeedUITestDocument else { return }
        didSeedUITestDocument = true

        let descriptor = FetchDescriptor<TypistDocument>(
            sortBy: [SortDescriptor(\TypistDocument.createdAt, order: .forward)]
        )
        let existingDocuments = (try? modelContext.fetch(descriptor)) ?? []

        if let existingSeed = existingDocuments.first(where: { $0.title == L10n.uiTestSampleDocumentTitle }) {
            selectedDocument = existingSeed
            return
        }

        let document = TypistDocument(title: L10n.uiTestSampleDocumentTitle, content: "")
        document.projectID = ProjectFileManager.uniqueFolderName(for: document.title)

        do {
            try ProjectFileManager.createInitialProject(for: document)
            try ProjectFileManager.writeTypFile(
                named: document.entryFileName,
                content: "= \(L10n.uiTestSampleDocumentTitle)\n\nHello, Typist UI tests.",
                for: document
            )
            modelContext.insert(document)
            selectedDocument = document
        } catch {
            try? ProjectFileManager.deleteProjectDirectory(for: document)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TypistDocument.self, inMemory: true)
}
