//
//  AppAppearanceManager.swift
//  Typist
//

import Foundation
import Observation
import SwiftUI

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

@Observable
final class AppAppearanceManager {
    private static let defaultsKey = "appAppearanceMode"

    var mode: String {
        didSet { UserDefaults.standard.set(mode, forKey: Self.defaultsKey) }
    }

    init() {
        mode = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? AppAppearanceMode.system.rawValue
    }

    var currentMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: mode) ?? .system
    }

    var colorScheme: ColorScheme? { currentMode.colorScheme }
}
