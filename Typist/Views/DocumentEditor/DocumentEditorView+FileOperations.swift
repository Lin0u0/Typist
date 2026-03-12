//
//  DocumentEditorView+FileOperations.swift
//  Typist
//

import Foundation
import SwiftUI

extension DocumentEditorView {
    func prepareDocumentForEditing() {
        ProjectFileManager.ensureProjectRoot(for: document)

        let typFiles = ProjectFileManager.listAllTypFiles(for: document)
        if document.requiresImportConfiguration || document.requiresInitialEntrySelection {
            let resolution = ProjectFileManager.resolveImportedEntryFile(from: typFiles)
            if let suggestedEntry = resolution.entryFileName {
                if !typFiles.contains(document.entryFileName) {
                    document.entryFileName = suggestedEntry
                }
                if resolution.requiresInitialSelection && document.importEntryFileOptions.isEmpty {
                    document.importEntryFileOptions = typFiles
                }
            }
            if !resolution.requiresInitialSelection {
                document.importEntryFileOptions = []
            }
            document.requiresInitialEntrySelection = resolution.requiresInitialSelection
            applyAutomaticImportDirectories()
            document.requiresImportConfiguration = document.requiresInitialEntrySelection
                || !document.importImageDirectoryOptions.isEmpty
                || !document.importFontDirectoryOptions.isEmpty
            if document.requiresImportConfiguration {
                showingImportConfiguration = true
                currentFileName = ""
                editorText = ""
                entrySource = ""
                return
            }
        }

        ProjectFileManager.migrateContentIfNeeded(for: document)
        loadFile(named: document.entryFileName)
    }

    func loadFile(named name: String) {
        saveTask?.cancel()
        saveTask = nil
        let text = (try? ProjectFileManager.readTypFile(named: name, for: document)) ?? ""
        currentFileName = name
        isLoadingFileContent = true
        editorText = text
        isLoadingFileContent = false
        lastPersistedText = text
        if name == document.entryFileName {
            entrySource = text
        }
    }

    func handleEditorTextChange(_ content: String) {
        guard !currentFileName.isEmpty else { return }
        if isEditingEntryFile {
            entrySource = content
        }
        scheduleSave(content: content, for: currentFileName)
    }

    func scheduleSave(content: String, for fileName: String) {
        guard fileName == currentFileName else { return }
        guard content != lastPersistedText else {
            saveTask?.cancel()
            saveTask = nil
            return
        }

        let fileURL = ProjectFileManager.typFileURL(named: fileName, for: document)
        let shouldRefreshPreviewAfterSave = fileName != document.entryFileName

        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            do {
                try await backgroundFileWriter.write(content, to: fileURL)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if self.currentFileName == fileName, self.editorText == content {
                        self.lastPersistedText = content
                        self.document.modifiedAt = Date()
                        if shouldRefreshPreviewAfterSave {
                            self.compileToken = UUID()
                        }
                    }
                    self.saveTask = nil
                }
            } catch {
                await MainActor.run {
                    self.fileSaveError = error.localizedDescription
                    self.saveTask = nil
                }
            }
        }
    }

    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        persistCurrentFileImmediately(content: editorText)
    }

    func persistCurrentFileImmediately(content: String) {
        guard !currentFileName.isEmpty else { return }
        guard content != lastPersistedText else { return }

        let shouldRefreshPreviewAfterSave = currentFileName != document.entryFileName
        let fileURL = ProjectFileManager.typFileURL(named: currentFileName, for: document)

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            lastPersistedText = content
            document.modifiedAt = Date()
            if shouldRefreshPreviewAfterSave {
                compileToken = UUID()
            }
        } catch {
            fileSaveError = error.localizedDescription
        }
    }

    func applyAutomaticImportDirectories() {
        if !ProjectFileManager.requiresImportDirectorySelection(document.importImageDirectoryOptions) {
            if let autoImageDirectory = ProjectFileManager.defaultImportDirectory(from: document.importImageDirectoryOptions) {
                document.imageDirectoryName = autoImageDirectory
            }
            document.importImageDirectoryOptions = []
        }

        if !ProjectFileManager.requiresImportDirectorySelection(document.importFontDirectoryOptions) {
            if let autoFontDirectory = ProjectFileManager.defaultImportDirectory(from: document.importFontDirectoryOptions) {
                _ = ProjectFileManager.importFontFiles(from: autoFontDirectory, for: document)
            }
            document.importFontDirectoryOptions = []
        }
    }

    func openFile(named name: String) {
        flushPendingSave()
        loadFile(named: name)
        InteractionFeedback.selection()
    }

    func compilePreviewNow() {
        flushPendingSave()
        pendingManualCompileFeedback = true
        compiler.compileNow(source: entrySource, fontPaths: compileFontPaths, rootDir: rootDir)
    }

    func clearCachesAndRecompile() {
        flushPendingSave()
        pendingManualCompileFeedback = true
        InteractionFeedback.notify(.warning)
        AccessibilitySupport.announce(L10n.a11yCacheRefreshStarted)
        let source = entrySource
        let fontPaths = compileFontPaths
        let rootDirectory = rootDir

        compiler.clearPreview()

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PreviewPackageCacheStore().clearAll()
                }.value
                await MainActor.run {
                    compiler.compileNow(source: source, fontPaths: fontPaths, rootDir: rootDirectory)
                }
            } catch {
                await MainActor.run {
                    previewActionError = error.localizedDescription
                }
            }
        }
    }

    @discardableResult
    func refreshCompileFontPaths() -> Bool {
        let latestPaths = FontManager.allFontPaths(for: document)
        guard latestPaths != compileFontPaths else { return false }
        compileFontPaths = latestPaths
        return true
    }

    func handleCompileInputsChanged() {
        guard refreshCompileFontPaths() else { return }
        guard canTriggerPreviewActions else { return }
        compileToken = UUID()
    }

    func refreshReferenceCompletions() {
        let projectDir = ProjectFileManager.projectDirectory(for: document)
        let fm = FileManager.default

        var bibEntries: [(key: String, type: String)] = []
        if let items = try? fm.contentsOfDirectory(atPath: projectDir.path) {
            for item in items where item.hasSuffix(".bib") {
                let url = projectDir.appendingPathComponent(item)
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    bibEntries.append(contentsOf: CompletionEngine.parseBibTeX(content))
                }
            }
        }
        cachedBibEntries = bibEntries

        let engine = CompletionEngine.shared
        var labels: [(name: String, kind: String)] = []
        let typFiles = ProjectFileManager.listAllTypFiles(for: document)
        for file in typFiles where file != currentFileName {
            if let content = try? ProjectFileManager.readTypFile(named: file, for: document) {
                labels.append(contentsOf: engine.scanLabels(in: content))
            }
        }
        cachedExternalLabels = labels

        refreshImageFiles()
    }

    func refreshImageFiles() {
        let allFiles = ProjectFileManager.listAllFiles(in: ProjectFileManager.projectDirectory(for: document))
        let imageExtensions = ProjectFileManager.supportedImageFileExtensions
        cachedImageFiles = allFiles.filter { path in
            let ext = (path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }
    }

    func triggerZipExport() {
        if appFontLibrary.isEmpty {
            flushPendingSave()
            exporter.exportZip(for: document)
        } else {
            showingZipExportWarning = true
        }
    }
}
