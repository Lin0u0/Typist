//
//  ProjectFileBrowserSheet.swift
//  Typist
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectFileBrowserSheet: View {
    @Bindable var document: TypistDocument
    var currentFileName: String
    var openFile: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var projectFiles: ProjectFiles = ProjectFiles(typFiles: [], imageFiles: [], fontFiles: [])
    @State private var showingNewFileAlert = false
    @State private var newFileName = ""
    @State private var showingImporter = false
    @State private var deleteError: String?
    @State private var showingDeleteError = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: .typ files
                Section {
                    if projectFiles.typFiles.isEmpty {
                        Text("No .typ files")
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(projectFiles.typFiles, id: \.self) { name in
                            Button {
                                openFile(name)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "doc.plaintext")
                                        .foregroundStyle(.secondary)
                                    Text(name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    badges(for: name)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTypFile(name)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(name == document.entryFileName)
                            }
                        }
                    }
                } header: {
                    Text("Source Files")
                }

                // MARK: Image files
                Section {
                    if projectFiles.imageFiles.isEmpty {
                        Text("No images")
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(projectFiles.imageFiles, id: \.self) { name in
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .foregroundStyle(.primary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteImageFile(name)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Images")
                }

                // MARK: Font files
                Section {
                    if projectFiles.fontFiles.isEmpty {
                        Text("No fonts")
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(projectFiles.fontFiles, id: \.self) { name in
                            HStack {
                                Image(systemName: "textformat")
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .foregroundStyle(.primary)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteFontFile(name)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Fonts")
                }
            }
            .navigationTitle("Project Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            newFileName = ""
                            showingNewFileAlert = true
                        } label: {
                            Label("New .typ File", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import File", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Source File", isPresented: $showingNewFileAlert) {
                TextField("filename.typ", text: $newFileName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Create") { createNewFile() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a name for the new .typ file.")
            }
            .alert("Error", isPresented: $showingDeleteError) {
                Button("OK") {}
            } message: {
                Text(deleteError ?? "")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { refreshFiles() }
    }

    // MARK: - Badges

    @ViewBuilder
    private func badges(for name: String) -> some View {
        HStack(spacing: 4) {
            if name == document.entryFileName {
                Text("Entry")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            if name == currentFileName {
                Text("Editing")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.green)
            }
        }
    }

    // MARK: - Actions

    private func refreshFiles() {
        projectFiles = ProjectFileManager.listProjectFiles(for: document)
    }

    private func createNewFile() {
        var name = newFileName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty && !name.hasSuffix(".typ") {
            name += ".typ"
        }
        guard !name.isEmpty else { return }
        do {
            try ProjectFileManager.createTypFile(named: name, for: document)
            refreshFiles()
            openFile(name)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
            showingDeleteError = true
        }
    }

    private func deleteTypFile(_ name: String) {
        do {
            try ProjectFileManager.deleteTypFile(named: name, for: document)
            refreshFiles()
        } catch {
            deleteError = error.localizedDescription
            showingDeleteError = true
        }
    }

    private func deleteImageFile(_ name: String) {
        let relativePath = "\(document.imageDirectoryName)/\(name)"
        try? ProjectFileManager.deleteProjectFile(relativePath: relativePath, for: document)
        refreshFiles()
    }

    private func deleteFontFile(_ name: String) {
        FontManager.deleteFont(fileName: name, from: document)
        document.fontFileNames.removeAll { $0 == name }
        refreshFiles()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let subdir: String
            if ["jpg", "jpeg", "png", "gif", "svg", "webp"].contains(ext) {
                subdir = document.imageDirectoryName
            } else if ["otf", "ttf", "woff", "woff2"].contains(ext) {
                subdir = "fonts"
            } else {
                // Import to project root
                subdir = ""
            }

            if subdir.isEmpty {
                // Copy directly into project root
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let dest = ProjectFileManager.projectDirectory(for: document)
                    .appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
            } else {
                _ = try? ProjectFileManager.importFile(from: url, to: subdir, for: document)
            }

            // Register imported font in document
            if ["otf", "ttf", "woff", "woff2"].contains(ext) {
                let name = url.lastPathComponent
                if !document.fontFileNames.contains(name) {
                    document.fontFileNames.append(name)
                }
            }
        }
        refreshFiles()
    }
}
