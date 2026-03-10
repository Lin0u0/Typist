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
    @State private var projectTree: [ProjectTreeNode] = []
    @State private var expandedNodes: Set<String> = []
    @State private var showingProjectSettings = false
    @State private var showingNewFileAlert = false
    @State private var newFileName = ""
    @State private var showingImporter = false
    @State private var actionError: String?
    @State private var showingActionError = false

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "webp"]
    private static let fontExtensions: Set<String> = ["otf", "ttf", "woff", "woff2"]

    var body: some View {
        NavigationStack {
            List {
                if projectTree.isEmpty {
                    Text("No files")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(projectTree) { node in
                        treeRow(for: node)
                    }
                }
            }
            .navigationTitle("Project Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingProjectSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }

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
        }
        .presentationDetents([.medium, .large])
        .onAppear { refreshProjectState() }
        .onChange(of: document.imageDirectoryName) { _, _ in
            refreshProjectState()
        }
        .sheet(isPresented: $showingProjectSettings, onDismiss: refreshProjectState) {
            ProjectSettingsSheet(document: document, openFile: openFile)
        }
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
                    .background(Color.accentColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
            if path == currentFileName {
                Text("Editing")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.16), in: Capsule())
                    .foregroundStyle(.green)
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
            return "character.textbox"
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

    private func present(_ error: Error) {
        actionError = error.localizedDescription
        showingActionError = true
    }
}
