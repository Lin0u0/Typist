//
//  ThemeManager.swift
//  Typist
//

import Observation
import Foundation

@Observable
final class ThemeManager {
    private static let defaultsKey = "editorThemeID"

    var themeID: String {
        didSet { UserDefaults.standard.set(themeID, forKey: Self.defaultsKey) }
    }

    init() {
        themeID = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "system"
    }

    var currentTheme: EditorTheme {
        switch themeID {
        case "mocha": return .mocha
        case "latte": return .latte
        default:      return .system
        }
    }
}
