//
//  TypstBridge.swift
//  Typist
//

import Foundation
import CoreText
import os.log

enum TypstBridgeError: Error, LocalizedError {
    case compilerNotLinked
    case compilationFailed(String)

    var errorDescription: String? {
        switch self {
        case .compilerNotLinked:
            return "Typst compiler library not linked. Run rust-ffi/build-ios.sh."
        case .compilationFailed(let msg):
            return msg
        }
    }
}

struct TypstBridge {
    /// Compile Typst source to PDF data.
    ///
    /// `nonisolated` so it can be called from `Task.detached` without
    /// crossing the MainActor boundary (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
    nonisolated static func compile(source: String) -> Result<Data, TypstBridgeError> {
#if TYPST_FFI_AVAILABLE
        // Collect system font file paths for CJK support.
        let fontPaths = cachedSystemFontPaths
        os_log(.debug, "TypstBridge: passing %d CJK font paths to Rust", fontPaths.count)
        for (i, p) in fontPaths.prefix(5).enumerated() {
            os_log(.debug, "TypstBridge: font[%d] = %{public}@", i, p as NSString)
        }

        // App caches directory for @preview package downloads.
        let cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("typst-packages")
            .path

        // Hold C strings alive for the duration of the FFI call.
        return source.withCString { cSource in
            // strdup gives UnsafeMutablePointer<CChar>; cast to const for the struct.
            let mutablePtrs: [UnsafeMutablePointer<CChar>?] = fontPaths.map { strdup($0) }
            defer { mutablePtrs.forEach { free($0) } }

            return mutablePtrs.withUnsafeBufferPointer { buf in
                // Reinterpret [UnsafeMutablePointer<CChar>?] as [UnsafePointer<CChar>?]
                let constBuf = UnsafeRawBufferPointer(buf)
                    .bindMemory(to: UnsafePointer<CChar>?.self)

                return (cacheDir ?? "").withCString { cCacheDir in
                    var opts = TypstOptions(
                        font_paths: constBuf.baseAddress,
                        font_path_count: buf.count,
                        cache_dir: cCacheDir
                    )
                    let result = typst_compile(cSource, &opts)
                    defer { typst_free_result(result) }

                    if result.success, let ptr = result.pdf_data {
                        return .success(Data(bytes: ptr, count: Int(result.pdf_len)))
                    } else if let errPtr = result.error_message {
                        return .failure(.compilationFailed(String(cString: errPtr)))
                    } else {
                        return .failure(.compilationFailed("Unknown compilation error"))
                    }
                }
            }
        }
#else
        return .failure(.compilerNotLinked)
#endif
    }

    // MARK: - System fonts (CJK support)

    /// Font file paths for CJK-capable system fonts, enumerated once via CoreText.
    ///
    /// Bundled typst-assets already provide Latin, Math, and Mono fonts, so we only
    /// supplement with CJK fonts here. Loading ALL system fonts (~2 GB) would OOM.
    private static let cjkFamilyPrefixes = [
        "PingFang", "Heiti", "Songti", "STHeiti", "STSong", "STFangsong",
        "STKaiti", "Hiragino", "Apple SD", "Noto Sans CJK", "Noto Serif CJK",
        "Source Han",
    ]

    private nonisolated static let cachedSystemFontPaths: [String] = {
        let descriptor = CTFontDescriptorCreateWithAttributes([:] as CFDictionary)
        guard let matched = CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil)
                as? [CTFontDescriptor] else { return [] }

        var seen = Set<URL>()
        var paths: [String] = []
        for desc in matched {
            guard
                let family = CTFontDescriptorCopyAttribute(desc, kCTFontFamilyNameAttribute) as? String,
                cjkFamilyPrefixes.contains(where: { family.hasPrefix($0) }),
                let url = CTFontDescriptorCopyAttribute(desc, kCTFontURLAttribute) as? URL,
                seen.insert(url).inserted
            else { continue }
            paths.append(url.path)
        }
        return paths
    }()
}
