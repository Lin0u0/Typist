//
//  SyncCoordinator.swift
//  Typist
//
//  Coordinates bidirectional sync between editor and preview,
//  preventing feedback loops via direction lock + cooldown.
//

import Foundation

struct PreviewScrollTarget: Equatable, Sendable {
    let page: Int
    let yPoints: Float
}

@MainActor @Observable
final class SyncCoordinator {
    enum Direction {
        case none
        case editorToPreview
        case previewToEditor
    }

    private(set) var activeDirection: Direction = .none
    private var lastSyncTime: ContinuousClock.Instant = .now
    private let cooldown: Duration = .milliseconds(150)

    /// Set by editor → preview sync; consumed by PreviewPane.
    var previewScrollTarget: PreviewScrollTarget?

    /// Set by preview → editor sync; consumed by DocumentEditorView.
    /// 1-based line number.
    var editorScrollTarget: Int?

    var isSyncEnabled: Bool = true

    /// Attempt to begin a sync in the given direction.
    /// Returns `true` if sync is allowed, `false` if blocked by cooldown or opposite direction.
    func beginSync(_ direction: Direction) -> Bool {
        guard isSyncEnabled else { return false }

        let now = ContinuousClock.now
        if activeDirection != .none && activeDirection != direction {
            if now - lastSyncTime < cooldown {
                return false
            }
        }

        activeDirection = direction
        lastSyncTime = now
        return true
    }

    func endSync() {
        activeDirection = .none
    }
}
