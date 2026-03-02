//
//  DocumentEditorView.swift
//  Typist
//

import SwiftUI
import SwiftData

struct DocumentEditorView: View {
    @Bindable var document: TypistDocument
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: Int = 0

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    EditorView(text: $document.content)
                    Divider()
                    PreviewPane(source: document.content)
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
                        PreviewPane(source: document.content)
                    }
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: document.content) {
            document.modifiedAt = Date()
        }
    }
}
