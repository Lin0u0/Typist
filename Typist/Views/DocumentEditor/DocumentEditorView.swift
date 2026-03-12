//
//  DocumentEditorView.swift
//  Typist
//

import SwiftUI
import SwiftData
import PDFKit
import PhotosUI

actor BackgroundDocumentFileWriter {
    func write(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct DocumentEditorView: View {
    enum ImageImportSource {
        case photoItem(PhotosPickerItem)
        case rawData(Data, suggestedFileName: String?)
        case fileURL(URL)
        case remoteURL(URL, suggestedFileName: String?)
    }

    @Bindable var document: TypistDocument
    var isSidebarVisible: Bool = false

    @Environment(AppFontLibrary.self) var appFontLibrary
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(ThemeManager.self) var themeManager

    @State var compiler = TypstCompiler()

    @State var currentFileName: String = ""
    @State var editorText: String = ""
    @State var entrySource: String = ""
    @State var compileToken: UUID = UUID()
    @State var isLoadingFileContent = false
    @State var lastPersistedText: String = ""
    @State var saveTask: Task<Void, Never>?
    @State var backgroundFileWriter = BackgroundDocumentFileWriter()
    @State var compileFontPaths: [String]

    @State var selectedTab: Int = 0
    @State var showingSlideshow = false
    @State var editorFraction: CGFloat = 0.5
    @State var showingPhotoPicker = false
    @State var showingFileBrowser = false
    @State var showingProjectSettings = false
    @State var selectedPhotoItems: [PhotosPickerItem] = []
    @State var insertionRequest: String?
    @State var findRequested = false
    @State var exporter = ExportController()
    @State var imageImportError: String?
    @State var fileSaveError: String?
    @State var previewActionError: String?
    @State var isImageDropTarget = false
    @State var pendingInsertionQueue: [String] = []
    @State var imageImportToast: String?
    @State var toastDismissTask: Task<Void, Never>?
    @State var showingImportConfiguration = false
    @State var showingZipExportWarning = false
    @State var focusCoordinator = EditorFocusCoordinator()
    @State var pendingManualCompileFeedback = false
    @State var cachedBibEntries: [(key: String, type: String)] = []
    @State var cachedExternalLabels: [(name: String, kind: String)] = []
    @State var cachedImageFiles: [String] = []

    var rootDir: String { ProjectFileManager.projectDirectory(for: document).path }
    var isEditingEntryFile: Bool { currentFileName == document.entryFileName }

    var completionFontFamilies: [String] {
        FontManager.completionFamilyNames(from: compileFontPaths)
    }

    init(document: TypistDocument, isSidebarVisible: Bool = false) {
        self.document = document
        self.isSidebarVisible = isSidebarVisible
        _compileFontPaths = State(initialValue: FontManager.allFontPaths(for: document))
    }

    var body: some View {
        editorOverlaysAndAlerts
    }
}
