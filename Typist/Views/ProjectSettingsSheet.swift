//
//  ProjectSettingsSheet.swift
//  Typist
//

import SwiftUI

struct ProjectSettingsSheet: View {
    @Bindable var document: TypistDocument
    var openFile: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var typFiles: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry File") {
                    Picker("Entry File", selection: $document.entryFileName) {
                        ForEach(typFiles, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: document.entryFileName) { _, newName in
                        openFile?(newName)
                    }
                }

                Section("Image Insertion") {
                    Picker("Format", selection: $document.imageInsertMode) {
                        Text("#image(\"path\")").tag("image")
                        Text("#figure(image(\"path\"), caption: [...])").tag("figure")
                    }
                }

                Section("Image Directory") {
                    TextField("Subdirectory name", text: $document.imageDirectoryName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Project Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            typFiles = ProjectFileManager.listProjectFiles(for: document).typFiles
            if typFiles.isEmpty {
                typFiles = [document.entryFileName]
            }
        }
    }
}
