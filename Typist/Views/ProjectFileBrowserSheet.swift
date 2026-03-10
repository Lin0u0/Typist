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

    @Environment(AppFontLibrary.self) private var appFontLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var projectTree: [ProjectTreeNode] = []
    @State private var entryFiles: [String] = []
    @State private var expandedNodes: Set<String> = []
    @State private var isSettingsExpanded = false
    @State private var showingNewFileAlert = false
    @State private var newFileName = ""
    @State private var showingImporter = false
    @State private var showingFontPicker = false
    @State private var actionError: String?
    @State private var showingActionError = false

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "webp"]
    private static let fontExtensions: Set<String> = ["otf", "ttf", "woff", "woff2"]

    var body: some View {
        NavigationStack {
            List {
                DisclosureGroup(isExpanded: $isSettingsExpanded) {
                    projectSettings
                } label: {
                    Label("Project Settings", systemImage: "gearshape")
                }

                if projectTree.isEmpty {
                    Text("No files")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(projectTree) { node in
                        treeRow(for: node)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.catppuccinBase)
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
            .alert("Error", isPresented: $showingActionError) {
                Button("OK") {}
            } message: {
                Text(actionError ?? "")
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .fileImporter(
                isPresented: $showingFontPicker,
                allowedContentTypes: [.font],
                allowsMultipleSelection: true
            ) { result in
                handleFontImport(result)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { refreshProjectState() }
        .onChange(of: document.imageDirectoryName) { _, _ in
            refreshProjectState()
        }
    }

    private var projectSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Entry File")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Entry File", selection: $document.entryFileName) {
                    ForEach(entryFiles, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: document.entryFileName) { _, newName in
                    openFile(newName)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Image Insertion")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Format", selection: $document.imageInsertMode) {
                    Text("#image(\"path\")").tag("image")
                    Text("#figure(image(\"path\"), caption: [...])").tag("figure")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Image Directory")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Subdirectory name", text: $document.imageDirectoryName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fonts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showingFontPicker = true
                    } label: {
                        Label("Add Font…", systemImage: "plus")
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                }

                Text("App Fonts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(appFontLibrary.items) { item in
                    HStack {
                        Label(item.displayName, systemImage: "textformat")
                            .font(.subheadline)
                            .foregroundStyle(item.isBuiltIn ? .secondary : .primary)
                        Spacer()
                        Text(item.isBuiltIn ? "built-in" : "app")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Project Fonts")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if document.fontFileNames.isEmpty {
                    Text("No project fonts")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(document.fontFileNames.sorted(), id: \.self) { name in
                        HStack {
                            Label(name, systemImage: "textformat")
                                .font(.subheadline)
                            Spacer()
                            Text("project")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func treeRow(for node: ProjectTreeNode) -> AnyView {
        if node.isDirectory {
            return AnyView(DisclosureGroup(isExpanded: expansionBinding(for: node.relativePath)) {
                ForEach(node.children) { child in
                    treeRow(for: child)
                }
            } label: {
                rowLabel(for: node)
            })
        } else if node.kind == .typ {
            return AnyView(Button {
                openFile(node.relativePath)
                dismiss()
            } label: {
                rowLabel(for: node)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    deleteTypFile(node.relativePath)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(node.relativePath == document.entryFileName)
            })
        } else {
            return AnyView(rowLabel(for: node)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteFile(at: node.relativePath, kind: node.kind)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                })
        }
    }

    private func rowLabel(for node: ProjectTreeNode) -> some View {
        HStack {
            Image(systemName: iconName(for: node))
                .foregroundStyle(.secondary)
            Text(node.displayName)
                .foregroundStyle(.primary)
            Spacer()
            if node.kind == .typ {
                badges(for: node.relativePath)
            }
        }
    }

    @ViewBuilder
    private func badges(for path: String) -> some View {
        HStack(spacing: 4) {
            if path == document.entryFileName {
                Text("Entry")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.catppuccinBlue.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.catppuccinBlue)
            }
            if path == currentFileName {
                Text("Editing")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.catppuccinSuccess.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.catppuccinSuccess)
            }
        }
    }

    private func iconName(for node: ProjectTreeNode) -> String {
        switch node.kind {
        case .directory:
            return "folder"
        case .typ:
            return "doc.plaintext"
        case .image:
            return "photo"
        case .font:
            return "textformat"
        case .other:
            return "doc"
        }
    }

    private func expansionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { expandedNodes.contains(path) },
            set: { isExpanded in
                if isExpanded {
                    expandedNodes.insert(path)
                } else {
                    expandedNodes.remove(path)
                }
            }
        )
    }

    private func refreshProjectState() {
        projectTree = ProjectFileManager.projectTree(for: document)
        let allTypFiles = ProjectFileManager.listAllTypFiles(for: document)
        entryFiles = allTypFiles.isEmpty ? [document.entryFileName] : allTypFiles
    }

    private func createNewFile() {
        var name = newFileName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty && !name.hasSuffix(".typ") {
            name += ".typ"
        }
        guard !name.isEmpty else { return }
        do {
            try ProjectFileManager.createTypFile(named: name, for: document)
            refreshProjectState()
            openFile(name)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func deleteTypFile(_ path: String) {
        do {
            try ProjectFileManager.deleteTypFile(named: path, for: document)
            refreshProjectState()
        } catch {
            present(error)
        }
    }

    private func deleteFile(at relativePath: String, kind: ProjectTreeNode.Kind) {
        do {
            try ProjectFileManager.deleteProjectFile(relativePath: relativePath, for: document)
            if kind == .font {
                document.fontFileNames.removeAll { $0 == (relativePath as NSString).lastPathComponent }
            }
            refreshProjectState()
        } catch {
            present(error)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result {
                present(error)
            }
            return
        }
        var firstError: Error?
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let subdir: String
            if Self.imageExtensions.contains(ext) {
                subdir = document.imageDirectoryName
            } else if Self.fontExtensions.contains(ext) {
                subdir = "fonts"
            } else {
                subdir = ""
            }

            do {
                _ = try ProjectFileManager.importFile(from: url, to: subdir, for: document)
                if Self.fontExtensions.contains(ext) {
                    let name = url.lastPathComponent
                    if !document.fontFileNames.contains(name) {
                        document.fontFileNames.append(name)
                    }
                }
            } catch {
                firstError = firstError ?? error
            }
        }
        refreshProjectState()
        if let firstError {
            present(firstError)
        }
    }

    private func handleFontImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result {
                present(error)
            }
            return
        }
        var firstError: Error?
        for url in urls {
            do {
                let name = try FontManager.importFont(from: url, for: document)
                if !document.fontFileNames.contains(name) {
                    document.fontFileNames.append(name)
                }
            } catch {
                firstError = firstError ?? error
            }
        }
        refreshProjectState()
        if let firstError {
            present(firstError)
        }
    }

    private func present(_ error: Error) {
        actionError = error.localizedDescription
        showingActionError = true
    }
}
