# Typist

A native iOS/iPadOS editor for [Typst](https://typst.app/) — the modern typesetting system.

## TestFlight

Join the beta on TestFlight: [https://testflight.apple.com/join/w5jmkR2T](https://testflight.apple.com/join/w5jmkR2T)

<p align="center">
  <img src="https://img.shields.io/badge/iOS%2026%20%26%20iPadOS%2026-blue" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift%205-orange" alt="Language">
  <img src="https://img.shields.io/badge/license-Apache%202-blue" alt="License">
</p>

## Features

- **Native Editing Experience** — Syntax-highlighted editor optimized for Typst markup
- **Live Preview** — Real-time PDF rendering as you type
- **Document Management** — Organize your documents with SwiftData persistence
- **PDF Export** — Generate publication-ready PDFs using the official Typst engine
- **Universal App** — Optimized for both iPhone and iPad with adaptive layout

## Screenshots

*(Screenshots coming soon)*

## Requirements

- iOS 17.0+ / iPadOS 17.0+
- Xcode 26.3+
- Swift 5

## Building

### Prerequisites

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/Typist.git
   cd Typist
   ```

2. Build the Rust FFI framework:
   ```bash
   cd rust-ffi
   ./build-ios.sh
   cd ..
   ```

3. Open the project in Xcode:
   ```bash
   open Typist.xcodeproj
   ```

4. Build and run on your device or simulator.

### Build Commands

```bash
# Debug build
xcodebuild -project Typist.xcodeproj -scheme Typist -configuration Debug build

# Release build
xcodebuild -project Typist.xcodeproj -scheme Typist -configuration Release build

# Run tests
xcodebuild test -project Typist.xcodeproj -scheme Typist -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Architecture

```
Typist/
├── TypistApp.swift          # App entry point
├── ContentView.swift        # Main split view layout
├── Models/
│   └── TypistDocument.swift # SwiftData model
├── Views/
│   ├── DocumentListView.swift
│   ├── DocumentEditorView.swift
│   ├── EditorView.swift
│   └── PreviewPane.swift
├── Editor/
│   ├── TypstTextView.swift  # Custom text editor
│   └── SyntaxHighlighter.swift
├── Compiler/
│   ├── TypstCompiler.swift  # Compilation interface
│   └── TypstBridge.swift    # FFI bridge
└── Bridging/
    └── Typist-Bridging-Header.h

rust-ffi/
├── Cargo.toml               # Rust dependencies (typst 0.14)
├── build-ios.sh             # Build script for iOS framework
└── src/
    └── lib.rs               # Rust FFI bindings
```

## Tech Stack

- **SwiftUI** — Declarative UI framework
- **SwiftData** — Modern data persistence
- **Typst 0.14** — Typesetting engine via Rust FFI
- **Rust** — FFI layer for Typst integration

## Acknowledgements

This project stands on the shoulders of giants. Special thanks to:

- **[Typst](https://github.com/typst/typst)** — The modern typesetting system that powers our PDF rendering. Typst is licensed under the Apache License 2.0.
  - `typst` — Core typesetting engine
  - `typst-pdf` — PDF export functionality
  - `typst-assets` — Font assets

- **[Apple Developer Documentation](https://developer.apple.com/documentation/)** — For SwiftUI, SwiftData, and iOS development resources.

- **[Rust FFI Working Group](https://github.com/rust-lang/nomicon)** — For the Rust FFI patterns and best practices that made the Swift-Rust bridge possible.
