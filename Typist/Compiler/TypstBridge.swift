//
//  TypstBridge.swift
//  Typist
//

import Foundation
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
    /// - Parameters:
    ///   - source: Typst markup source string.
    ///   - fontPaths: File paths to font files (bundled + user-imported).
    ///
    /// `nonisolated` so it can be called from `Task.detached` without
    /// crossing the MainActor boundary (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
    nonisolated static func compile(source: String, fontPaths: [String], rootDir: String? = nil) -> Result<Data, TypstBridgeError> {
#if TYPST_FFI_AVAILABLE
        os_log(.debug, "TypstBridge: passing %d font paths to Rust", fontPaths.count)
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
            let mutablePtrs: [UnsafeMutablePointer<CChar>?] = fontPaths.map { strdup($0) }
            defer { mutablePtrs.forEach { free($0) } }

            return mutablePtrs.withUnsafeBufferPointer { buf in
                let constBuf = UnsafeRawBufferPointer(buf)
                    .bindMemory(to: UnsafePointer<CChar>?.self)

                return (cacheDir ?? "").withCString { cCacheDir in
                  return (rootDir ?? "").withCString { cRootDir in
                    var opts = TypstOptions(
                        font_paths: constBuf.baseAddress,
                        font_path_count: buf.count,
                        cache_dir: cCacheDir,
                        root_dir: rootDir != nil ? cRootDir : nil
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
        }
#else
        return .failure(.compilerNotLinked)
#endif
    }
}
