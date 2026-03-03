//
//  ProjectSettingsSheet.swift
//  Typist
//

import SwiftUI

struct ProjectSettingsSheet: View {
    @Bindable var document: TypistDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
        .presentationDetents([.medium])
    }
}
