import XCTest

final class FarFlowUITests: XCTestCase {
    @MainActor func testCoreNavigationAndLocalEditing() throws {
        let app=XCUIApplication();app.launchArguments=["--ui-testing"]
        app.launchEnvironment["FAR_FLOW_DATA_DIR"]=NSTemporaryDirectory()+"FarFlow-UI-"+UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["nav.dictionary"].waitForExistence(timeout:10))
        app.buttons["nav.dictionary"].click();app.buttons["dictionary.add"].click()
        let word=app.textFields["dictionary.word"];XCTAssertTrue(word.waitForExistence(timeout:3));word.click();word.typeText("Far Flow Test")
        app.buttons["Save word"].click();XCTAssertTrue(app.staticTexts["Far Flow Test"].waitForExistence(timeout:3))
        for page in ["snippets","styles","transforms","notes","insights","models","settings","dictation"] {app.buttons["nav."+page].click()}
        XCTAssertTrue(app.textFields["history.search"].exists)
        app.terminate()
    }
    @MainActor func testNotesCloseReopenAndQuit() throws {
        let app=XCUIApplication(); app.launchArguments=["--ui-testing"]
        let directory=NSTemporaryDirectory()+"FarFlow-Notes-"+UUID().uuidString
        app.launchEnvironment["FAR_FLOW_DATA_DIR"]=directory
        defer { app.terminate(); try? FileManager.default.removeItem(atPath:directory) }
        app.launch()
        XCTAssertTrue(app.buttons["nav.notes"].waitForExistence(timeout:10))
        app.typeKey("n",modifierFlags:.command)
        let title=app.textFields["notes.title"], editor=app.textViews["notes.editor"]
        XCTAssertTrue(title.waitForExistence(timeout:3))
        title.click(); title.typeKey("a",modifierFlags:.command); title.typeText("Lifecycle test")
        editor.click(); editor.typeText("Saved before closing.")
        app.typeKey("w",modifierFlags:.command)
        XCTAssertNotEqual(app.state,.notRunning)
        app.activate()
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Far Flow"].click()
        XCTAssertTrue(editor.waitForExistence(timeout:5))
        XCTAssertEqual(editor.value as? String,"Saved before closing.")
        app.typeKey("n",modifierFlags:.command)
        XCTAssertEqual(editor.value as? String,"")
        editor.click(); editor.typeText("Second note.")
        app.typeKey("q",modifierFlags:.command)
        XCTAssertTrue(app.wait(for:.notRunning,timeout:8))
        app.launch()
        app.buttons["nav.notes"].click()
        XCTAssertTrue(editor.waitForExistence(timeout:5))
        XCTAssertEqual(editor.value as? String,"Second note.")
        let search=app.textFields["notes.search"]
        search.click(); search.typeText("Saved before")
        XCTAssertTrue(app.staticTexts["Lifecycle test"].waitForExistence(timeout:3))
    }
}
