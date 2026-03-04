//
//  TypistTests.swift
//  TypistTests
//
//  Created by Lin Qidi on 2026/3/2.
//

import Foundation
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
        defer { ProjectFileManager.deleteProjectDirectory(for: doc) }

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
        defer { ProjectFileManager.deleteProjectDirectory(for: doc) }

        let srcDir = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: srcDir) }
        let src = srcDir.appendingPathComponent("hello.txt")
        try Data("hello".utf8).write(to: src)

        let importedPath = try ProjectFileManager.importFile(from: src, to: "", for: doc)
        #expect(importedPath == "hello.txt")

        let dest = ProjectFileManager.projectDirectory(for: doc).appendingPathComponent("hello.txt")
        #expect(FileManager.default.fileExists(atPath: dest.path))
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
