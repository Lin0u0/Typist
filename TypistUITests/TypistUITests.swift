//
//  TypistUITests.swift
//  TypistUITests
//
//  Created by Lin Qidi on 2026/3/2.
//

import XCTest

final class TypistUITests: XCTestCase {
    private func launchApp(seedDocument: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        if seedDocument {
            app.launchArguments.append("UITEST_SEED_SAMPLE_DOCUMENT")
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["document-list.settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["document-list.sort"].exists)
        XCTAssertTrue(app.buttons["document-list.add"].exists)
    }

    @MainActor
    func testSettingsScreenExposesPrimaryEntries() throws {
        let app = launchApp()

        app.buttons["document-list.settings"].tap()

        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.import-zip"].exists)
        XCTAssertTrue(app.buttons["settings.fonts"].exists)
        XCTAssertTrue(app.buttons["settings.cache"].exists)
    }

    @MainActor
    func testSeededDocumentExposesEditorPrimaryControls() throws {
        let app = launchApp(seedDocument: true)

        if !app.buttons["editor.share"].waitForExistence(timeout: 3) {
            let seededRow = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "document-list.row.")
            ).firstMatch
            XCTAssertTrue(seededRow.waitForExistence(timeout: 5))
            seededRow.tap()
        }

        XCTAssertTrue(app.buttons["editor.share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor.more-menu"].exists)
        XCTAssertTrue(app.segmentedControls["editor.mode-picker"].exists || app.otherElements["editor.preview"].exists)
    }
}
