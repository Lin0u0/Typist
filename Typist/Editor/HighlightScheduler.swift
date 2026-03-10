//
//  HighlightScheduler.swift
//  Typist
//

import Foundation

enum HighlightMode {
    case immediate
    case debounced
}

@MainActor
final class HighlightScheduler {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let delay: Duration
    private let sleep: Sleep
    private let action: @MainActor () -> Void

    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        delay: Duration = .milliseconds(100),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        action: @escaping @MainActor () -> Void
    ) {
        self.delay = delay
        self.sleep = sleep
        self.action = action
    }

    func schedule(_ mode: HighlightMode) {
        generation &+= 1
        let currentGeneration = generation

        task?.cancel()
        task = nil

        switch mode {
        case .immediate:
            action()
        case .debounced:
            task = Task { [delay, sleep, action] in
                do {
                    try await sleep(delay)
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard currentGeneration == self.generation else { return }
                    self.task = nil
                    action()
                }
            }
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}
