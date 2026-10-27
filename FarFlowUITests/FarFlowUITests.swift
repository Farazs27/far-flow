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
        for page in ["snippets","styles","transforms","scratchpad","insights","models","settings","dictation"] {app.buttons["nav."+page].click()}
        XCTAssertTrue(app.textFields["history.search"].exists)
        app.terminate()
    }
}
