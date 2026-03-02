# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Typist is a native iOS/iPadOS app built with **Swift 5**, **SwiftUI**, and **SwiftData**. It targets iOS 26.2+ and supports both iPhone and iPad (NavigationSplitView layout).

## Build & Test Commands

```bash
# Build (Debug)
xcodebuild -project Typist.xcodeproj -scheme Typist -configuration Debug build

# Build (Release)
xcodebuild -project Typist.xcodeproj -scheme Typist -configuration Release build

# Run all tests
xcodebuild test -project Typist.xcodeproj -scheme Typist -destination 'platform=iOS Simulator,name=iPhone 16'

# Run only unit tests
xcodebuild test -project Typist.xcodeproj -scheme Typist -only-testing:TypistTests -destination 'platform=iOS Simulator,name=iPhone 16'

# Run only UI tests
xcodebuild test -project Typist.xcodeproj -scheme Typist -only-testing:TypistUITests -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Architecture

- **TypistApp.swift**: App entry point, configures the SwiftData `ModelContainer`
- **ContentView.swift**: Main UI using `NavigationSplitView` with list/detail layout
- **Item.swift**: SwiftData `@Model` class (data layer)
- **TypistTests/**: Unit tests using Swift Testing (`@Test` macro)
- **TypistUITests/**: UI tests using XCTest (`XCUIApplication`)

## Key Conventions

- SwiftUI declarative views with `@Query` for reactive SwiftData binding
- `@MainActor` isolation is the default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
- Automatic Info.plist generation (no manual Info.plist file)
- No external dependencies or package manager — pure Apple frameworks
