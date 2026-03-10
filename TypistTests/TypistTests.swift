//
//  TypistTests.swift
//  TypistTests
//
//  Created by Lin Qidi on 2026/3/2.
//

import Foundation
import PDFKit
import Testing
@testable import Typist

struct TypistTests {

    @Test func zipImporterRejectsParentTraversalPath() throws {
        let zip = makeStoredZip(entries: [
            ("../evil.txt", Data("x".utf8))
        ])
        let dest = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dest) }

        var gotUnsafePath = false
        do {
            _ = try ZipImporter.extract(data: zip, to: dest)
        } catch let error as ZipImporterError {
            if case .unsafePath = error {
                gotUnsafePath = true
            }
        } catch {}
        #expect(gotUnsafePath)
    }

    @Test func zipImporterExtractsSingleTopLevelDirectory() throws {
        let zip = makeStoredZip(entries: [
            ("project/main.typ", Data("Hello".utf8)),
            ("project/images/a.png", Data([0x01, 0x02, 0x03]))
        ])
        let dest = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dest) }

        let extracted = try ZipImporter.extract(data: zip, to: dest).sorted()
        #expect(extracted == ["images/a.png", "main.typ"])

        let main = dest.appendingPathComponent("main.typ")
        let image = dest.appendingPathComponent("images/a.png")
        #expect(FileManager.default.fileExists(atPath: main.path))
        #expect(FileManager.default.fileExists(atPath: image.path))
    }

    @Test func projectFileManagerRejectsUnsafeRelativePaths() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        ProjectFileManager.ensureProjectStructure(for: doc)
        defer { try? ProjectFileManager.deleteProjectDirectory(for: doc) }

        var deleteUnsafe = false
        do {
            try ProjectFileManager.deleteProjectFile(relativePath: "../oops.txt", for: doc)
        } catch let error as TypistFileError {
            if case .unsafePath = error {
                deleteUnsafe = true
            }
        } catch {}
        #expect(deleteUnsafe)

        var createInvalidName = false
        do {
            try ProjectFileManager.createTypFile(named: "../bad.typ", for: doc)
        } catch let error as TypistFileError {
            if case .invalidFileName = error {
                createInvalidName = true
            }
        } catch {}
        #expect(createInvalidName)
    }

    @Test func projectFileManagerImportFileAllowsEmptySubdirAndReturnsFileName() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        ProjectFileManager.ensureProjectStructure(for: doc)
        defer { try? ProjectFileManager.deleteProjectDirectory(for: doc) }

        let srcDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: srcDir) }
        let src = srcDir.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: src)

        let importedPath = try ProjectFileManager.importFile(from: src, to: "", for: doc)
        #expect(importedPath == "hello.txt")

        let dest = ProjectFileManager.projectDirectory(for: doc).appendingPathComponent("hello.txt")
        #expect(FileManager.default.fileExists(atPath: dest.path))
    }

    @Test func resolveImportedEntryFileRequiresSelectionWhenMainTypIsMissing() {
        let resolution = ProjectFileManager.resolveImportedEntryFile(from: ["chapter.typ", "appendix.typ"])

        #expect(resolution.entryFileName == "appendix.typ")
        #expect(resolution.requiresInitialSelection)
    }

    @Test func migrateContentIfNeededSkipsEmptyContent() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        ProjectFileManager.ensureProjectStructure(for: doc)
        defer { try? ProjectFileManager.deleteProjectDirectory(for: doc) }

        ProjectFileManager.migrateContentIfNeeded(for: doc)

        let entryURL = ProjectFileManager.entryFileURL(for: doc)
        #expect(!FileManager.default.fileExists(atPath: entryURL.path))
    }

    @Test func projectFileManagerSupportsNestedTypPaths() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        ProjectFileManager.ensureProjectStructure(for: doc)
        defer { try? ProjectFileManager.deleteProjectDirectory(for: doc) }

        let nestedDir = ProjectFileManager.projectDirectory(for: doc).appendingPathComponent("chapters", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        try ProjectFileManager.writeTypFile(named: "chapters/intro.typ", content: "Hello", for: doc)

        let loaded = try ProjectFileManager.readTypFile(named: "chapters/intro.typ", for: doc)
        #expect(loaded == "Hello")

        try ProjectFileManager.deleteTypFile(named: "chapters/intro.typ", for: doc)
        #expect(!FileManager.default.fileExists(atPath: nestedDir.appendingPathComponent("intro.typ").path))
    }

    @Test func projectFileManagerBuildsProjectTreeFromRoot() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        ProjectFileManager.ensureProjectStructure(for: doc)
        defer { try? ProjectFileManager.deleteProjectDirectory(for: doc) }

        try ProjectFileManager.writeTypFile(named: "main.typ", content: "", for: doc)
        let chapterDir = ProjectFileManager.projectDirectory(for: doc).appendingPathComponent("chapters", isDirectory: true)
        try FileManager.default.createDirectory(at: chapterDir, withIntermediateDirectories: true)
        try ProjectFileManager.writeTypFile(named: "chapters/intro.typ", content: "", for: doc)

        let imageURL = ProjectFileManager.imagesDirectory(for: doc).appendingPathComponent("cover.png")
        try Data([0x01]).write(to: imageURL)

        let tree = ProjectFileManager.projectTree(for: doc)

        #expect(tree.map(\.displayName) == ["chapters", "fonts", "images", "main.typ"])
        let chapters = try #require(tree.first(where: { $0.relativePath == "chapters" }))
        #expect(chapters.children.map(\.relativePath) == ["chapters/intro.typ"])
        let images = try #require(tree.first(where: { $0.relativePath == "images" }))
        #expect(images.children.map(\.relativePath) == ["images/cover.png"])
    }

    @Test func projectFileManagerListsAllFilesRecursively() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        ProjectFileManager.ensureProjectStructure(for: doc)
        defer { try? ProjectFileManager.deleteProjectDirectory(for: doc) }

        try ProjectFileManager.writeTypFile(named: "main.typ", content: "", for: doc)
        let nestedImage = ProjectFileManager.projectDirectory(for: doc)
            .appendingPathComponent("assets/icons", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedImage, withIntermediateDirectories: true)
        try Data([0x01]).write(to: nestedImage.appendingPathComponent("logo.png"))

        let files = ProjectFileManager.listAllFiles(in: ProjectFileManager.projectDirectory(for: doc))
        #expect(files == ["assets/icons/logo.png", "main.typ"])
    }

    @Test func projectFileManagerFindsImportDirectoryCandidates() {
        let files = [
            "main.typ",
            "assets/cover.png",
            "assets/diagram.svg",
            "fonts/Inter-Regular.otf",
            "vendor/fonts/Mono.ttf",
            "vendor/fonts/nested/Mono-Bold.ttf",
            "logo.jpg"
        ]

        #expect(ProjectFileManager.imageDirectoryCandidates(from: files) == ["", "assets"])
        #expect(ProjectFileManager.fontDirectoryCandidates(from: files) == ["", "fonts", "vendor", "vendor/fonts", "vendor/fonts/nested"])
    }

    @Test func projectFileManagerRecognizesOnlyRealImportChoices() {
        #expect(!ProjectFileManager.requiresImportDirectorySelection([""]))
        #expect(!ProjectFileManager.requiresImportDirectorySelection(["images"]))
        #expect(ProjectFileManager.requiresImportDirectorySelection(["", "images"]))
        #expect(ProjectFileManager.defaultImportDirectory(from: [""]) == String?.some(""))
        #expect(ProjectFileManager.defaultImportDirectory(from: ["images"]) == String?.some("images"))
        #expect(ProjectFileManager.defaultImportDirectory(from: ["", "images"]) == nil)
        #expect(ProjectFileManager.defaultImportDirectory(from: []) == nil)
    }

    @Test func projectFileManagerRenameThrowsWhenProjectDirectoryIsMissing() {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")

        var gotMissingProject = false
        do {
            _ = try ProjectFileManager.renameProjectDirectory(for: doc, to: "Renamed")
        } catch let error as TypistFileError {
            if case .fileNotFound(let name) = error {
                gotMissingProject = (name == doc.projectID)
            }
        } catch {}

        #expect(gotMissingProject)
    }

    @Test func projectFileManagerAllowsRootImageDirectory() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        doc.imageDirectoryName = ""
        ProjectFileManager.ensureProjectStructure(for: doc)
        defer { try? ProjectFileManager.deleteProjectDirectory(for: doc) }

        let relativePath = try ProjectFileManager.saveImage(data: Data([0x01]), fileName: "cover.png", for: doc)

        #expect(relativePath == "cover.png")
        #expect(FileManager.default.fileExists(atPath: ProjectFileManager.projectDirectory(for: doc).appendingPathComponent("cover.png").path))
    }

    @MainActor
    @Test func highlightSchedulerCoalescesBurstUpdates() async {
        let counter = LockedCounter()
        let scheduler = HighlightScheduler(sleep: { _ in }) {
            counter.increment()
        }

        scheduler.schedule(.debounced)
        scheduler.schedule(.debounced)
        scheduler.schedule(.debounced)

        await waitUntil {
            counter.value == 1
        }
        #expect(counter.value == 1)
    }

    @MainActor
    @Test func highlightSchedulerImmediateUpdateCancelsPendingDebounce() async {
        let counter = LockedCounter()
        let scheduler = HighlightScheduler(
            sleep: { _ in try await Task.sleep(for: .seconds(1)) }
        ) {
            counter.increment()
        }

        scheduler.schedule(.debounced)
        scheduler.schedule(.immediate)

        await waitUntil {
            counter.value == 1
        }
        #expect(counter.value == 1)
    }

    @MainActor
    @Test func typstCompilerDropsIntermediateDebouncedRequests() async {
        let probe = CompileProbe()
        probe.block("first")

        let compiler = TypstCompiler(
            compileWorker: { source, _, _ in probe.compile(source: source) },
            documentBuilder: { _ in PDFDocument() },
            sleep: { _ in }
        )

        compiler.compile(source: "first", fontPaths: [], rootDir: nil)
        await waitUntil {
            probe.startedSources == ["first"]
        }

        compiler.compile(source: "second", fontPaths: [], rootDir: nil)
        compiler.compile(source: "third", fontPaths: [], rootDir: nil)

        probe.release("first")

        await waitUntil {
            probe.startedSources.count == 2 && !compiler.isCompiling
        }

        #expect(probe.startedSources == ["first", "third"])
        #expect(probe.maxConcurrent == 1)
    }

    @MainActor
    @Test func typstCompilerCompileNowReplacesPendingRequestWithoutParallelism() async {
        let probe = CompileProbe()
        probe.block("first")

        let compiler = TypstCompiler(
            compileWorker: { source, _, _ in probe.compile(source: source) },
            documentBuilder: { _ in PDFDocument() },
            sleep: { _ in }
        )

        compiler.compileNow(source: "first", fontPaths: [], rootDir: nil)
        await waitUntil {
            probe.startedSources == ["first"]
        }

        compiler.compile(source: "second", fontPaths: [], rootDir: nil)
        compiler.compileNow(source: "third", fontPaths: [], rootDir: nil)

        probe.release("first")

        await waitUntil {
            probe.startedSources.count == 2 && !compiler.isCompiling
        }

        #expect(probe.startedSources == ["first", "third"])
        #expect(probe.maxConcurrent == 1)
    }

    @Test func appFontLibraryImportsDeletesAndReloadsCustomFonts() throws {
        let appRoot = makeTempDirectory()
        let sourceRoot = makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: appRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let inter = sourceRoot.appendingPathComponent("Inter-Regular.otf")
        let mono = sourceRoot.appendingPathComponent("Mono.ttf")
        try Data("inter".utf8).write(to: inter)
        try Data("mono".utf8).write(to: mono)

        let library = AppFontLibrary(rootURL: appRoot)
        #expect(library.isEmpty)

        try library.importFonts(from: [mono, inter])

        #expect(library.fileNames == ["Inter-Regular.otf", "Mono.ttf"])
        #expect(FileManager.default.fileExists(atPath: FontManager.appFontsDirectory(rootURL: appRoot).appendingPathComponent("Inter-Regular.otf").path))

        library.delete(fileName: "Inter-Regular.otf")

        #expect(library.fileNames == ["Mono.ttf"])

        let reloaded = AppFontLibrary(rootURL: appRoot)
        #expect(reloaded.fileNames == ["Mono.ttf"])
        #expect(!reloaded.isEmpty)
    }

    @Test func fontManagerAllFontPathsKeepsProjectFontsAheadOfAppFonts() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        let appRoot = makeTempDirectory()
        let sourceRoot = makeTempDirectory()
        defer {
            try? ProjectFileManager.deleteProjectDirectory(for: doc)
            try? FileManager.default.removeItem(at: appRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        ProjectFileManager.ensureProjectStructure(for: doc)

        let projectFontName = "ProjectOverride.ttf"
        let projectFontURL = ProjectFileManager.fontsDirectory(for: doc).appendingPathComponent(projectFontName)
        try Data("project".utf8).write(to: projectFontURL)
        doc.fontFileNames = [projectFontName]

        let appFontSource = sourceRoot.appendingPathComponent("GlobalFallback.otf")
        try Data("app".utf8).write(to: appFontSource)
        try FontManager.importAppFont(from: appFontSource, rootURL: appRoot)

        let paths = FontManager.allFontPaths(for: doc, appRootURL: appRoot)
        let builtInCount = FontManager.bundledCJKFontPaths.count

        #expect(Array(paths.prefix(builtInCount)) == FontManager.bundledCJKFontPaths)
        #expect(Array(paths.dropFirst(builtInCount)) == [
            projectFontURL.path,
            FontManager.appFontsDirectory(rootURL: appRoot).appendingPathComponent("GlobalFallback.otf").path,
        ])
    }

    @Test func zipProjectDoesNotIncludeAppFonts() throws {
        let doc = makeDocument(projectID: "tests-\(UUID().uuidString)")
        let appRoot = makeTempDirectory()
        let sourceRoot = makeTempDirectory()
        defer {
            try? ProjectFileManager.deleteProjectDirectory(for: doc)
            try? FileManager.default.removeItem(at: appRoot)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        try ProjectFileManager.createInitialProject(for: doc)
        try ProjectFileManager.writeTypFile(named: "main.typ", content: "= Hello", for: doc)

        let appFontSource = sourceRoot.appendingPathComponent("GlobalOnly.otf")
        try Data("global".utf8).write(to: appFontSource)
        try FontManager.importAppFont(from: appFontSource, rootURL: appRoot)

        let zipURL = try ExportManager.zipProject(for: doc)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let extractRoot = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: extractRoot) }

        let extracted = try ZipImporter.extract(from: zipURL, to: extractRoot)

        #expect(!extracted.contains("GlobalOnly.otf"))
        #expect(FileManager.default.fileExists(atPath: extractRoot.appendingPathComponent("main.typ").path))
    }

    @Test func previewPackageCacheSnapshotListsPackagesAndTotalSize() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeCachePackage(root: root, namespace: "preview", name: "touying", version: "0.6.2", files: [
            ("package.typ", Data("hello".utf8)),
            ("assets/icon.bin", Data([0x00, 0x01, 0x02]))
        ])
        try makeCachePackage(root: root, namespace: "preview", name: "charged-ieee", version: "0.1.4", files: [
            ("template.typ", Data("abc".utf8))
        ])

        let snapshot = try PreviewPackageCacheStore(rootURL: root).snapshot()

        #expect(snapshot.entries.map(\.id) == [
            "preview/charged-ieee/0.1.4",
            "preview/touying/0.6.2"
        ])
        #expect(snapshot.totalSizeInBytes == 11)
    }

    @Test func previewPackageCacheRemoveDeletesPackageAndCleansEmptyParents() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeCachePackage(root: root, namespace: "preview", name: "touying", version: "0.6.2", files: [
            ("package.typ", Data("hello".utf8))
        ])

        let store = PreviewPackageCacheStore(rootURL: root)
        let entry = try #require(store.snapshot().entries.first)

        try store.remove(entry)

        let remainingSnapshot = try store.snapshot()
        #expect(remainingSnapshot.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("preview").path))
    }

    @Test func previewPackageCacheClearAllLeavesEmptyRootDirectory() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try makeCachePackage(root: root, namespace: "preview", name: "touying", version: "0.6.2", files: [
            ("package.typ", Data("hello".utf8))
        ])

        let store = PreviewPackageCacheStore(rootURL: root)
        try store.clearAll()

        #expect(FileManager.default.fileExists(atPath: root.path))
        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        #expect(contents.isEmpty)
    }

    private func makeDocument(projectID: String) -> TypistDocument {
        let doc = TypistDocument(title: "Test", content: "")
        doc.projectID = projectID
        doc.entryFileName = "main.typ"
        doc.imageDirectoryName = "images"
        return doc
    }

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TypistTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeCachePackage(
        root: URL,
        namespace: String,
        name: String,
        version: String,
        files: [(path: String, data: Data)]
    ) throws {
        let versionDir = root
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)

        for file in files {
            let fileURL = versionDir.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: fileURL)
        }
    }

    /// Build a minimal ZIP containing STORE entries only. Sufficient for parser regression tests.
    private func makeStoredZip(entries: [(name: String, data: Data)]) -> Data {
        var localSection = Data()
        var centralSection = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let dataBytes = [UInt8](entry.data)
            offsets.append(UInt32(localSection.count))

            localSection.appendU32LE(0x0403_4B50)
            localSection.appendU16LE(20)
            localSection.appendU16LE(0)
            localSection.appendU16LE(0)
            localSection.appendU16LE(0)
            localSection.appendU16LE(0)
            localSection.appendU32LE(0)
            localSection.appendU32LE(UInt32(dataBytes.count))
            localSection.appendU32LE(UInt32(dataBytes.count))
            localSection.appendU16LE(UInt16(nameBytes.count))
            localSection.appendU16LE(0)
            localSection.append(contentsOf: nameBytes)
            localSection.append(contentsOf: dataBytes)
        }

        for (index, entry) in entries.enumerated() {
            let nameBytes = Array(entry.name.utf8)
            let dataCount = UInt32(entry.data.count)

            centralSection.appendU32LE(0x0201_4B50)
            centralSection.appendU16LE(20)
            centralSection.appendU16LE(20)
            centralSection.appendU16LE(0)
            centralSection.appendU16LE(0)
            centralSection.appendU16LE(0)
            centralSection.appendU16LE(0)
            centralSection.appendU32LE(0)
            centralSection.appendU32LE(dataCount)
            centralSection.appendU32LE(dataCount)
            centralSection.appendU16LE(UInt16(nameBytes.count))
            centralSection.appendU16LE(0)
            centralSection.appendU16LE(0)
            centralSection.appendU16LE(0)
            centralSection.appendU16LE(0)
            centralSection.appendU32LE(0)
            centralSection.appendU32LE(offsets[index])
            centralSection.append(contentsOf: nameBytes)
        }

        let centralOffset = UInt32(localSection.count)
        let centralSize = UInt32(centralSection.count)
        var eocd = Data()
        eocd.appendU32LE(0x0605_4B50)
        eocd.appendU16LE(0)
        eocd.appendU16LE(0)
        eocd.appendU16LE(UInt16(entries.count))
        eocd.appendU16LE(UInt16(entries.count))
        eocd.appendU32LE(centralSize)
        eocd.appendU32LE(centralOffset)
        eocd.appendU16LE(0)

        return localSection + centralSection + eocd
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock {
            storage += 1
        }
    }
}

private final class CompileProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started: [String] = []
    private var blockers: [String: DispatchSemaphore] = [:]
    private var activeCount = 0
    private var maxActiveCount = 0

    var startedSources: [String] {
        lock.withLock { started }
    }

    var maxConcurrent: Int {
        lock.withLock { maxActiveCount }
    }

    func block(_ source: String) {
        lock.withLock {
            blockers[source] = DispatchSemaphore(value: 0)
        }
    }

    func release(_ source: String) {
        lock.withLock {
            blockers.removeValue(forKey: source)?.signal()
        }
    }

    func compile(source: String) -> Result<Data, TypstBridgeError> {
        let blocker = lock.withLock { () -> DispatchSemaphore? in
            started.append(source)
            activeCount += 1
            maxActiveCount = max(maxActiveCount, activeCount)
            return blockers[source]
        }

        blocker?.wait()

        lock.withLock {
            activeCount -= 1
        }
        return .success(Data(source.utf8))
    }
}

private extension Data {
    mutating func appendU16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendU32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
