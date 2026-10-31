import XCTest
import AppKit
import ApplicationServices

final class InsertionTests: XCTestCase {
    private func range(_ location: Int,_ length: Int) -> AXValue {
        var value=CFRange(location:location,length:length)
        return AXValueCreate(.cfRange,&value)!
    }
    func testWebEditorsUsePasteRatherThanAcknowledgedAXWrites() {
        for app in ["com.openai.codex","com.openai.chat","com.microsoft.VSCode","com.google.Chrome"] {
            XCTAssertTrue(InsertionVerification.prefersPaste(bundleID:app))
        }
        XCTAssertFalse(InsertionVerification.prefersPaste(bundleID:"com.apple.TextEdit"))
    }
    func testExactInsertionAndSelectionReplacement() {
        XCTAssertTrue(InsertionVerification.confirmed(before:"Hello world",after:"Hello there",selection:range(6,5),text:"there"))
        XCTAssertTrue(InsertionVerification.confirmed(before:"Hello ",after:"Hello world",selection:range(6,0),text:"world"))
        XCTAssertTrue(InsertionVerification.confirmed(before:"😀 hi",after:"😀 hello",selection:range(3,2),text:"hello"))
        XCTAssertTrue(InsertionVerification.confirmed(before:"hello",after:"hello",selection:range(0,5),text:"hello"))
    }
    func testExistingTextElsewhereDoesNotFalselyConfirmInsertion() {
        XCTAssertFalse(InsertionVerification.confirmed(before:"hello world",after:"hello world!",selection:range(0,0),text:"hello"))
        XCTAssertFalse(InsertionVerification.confirmed(before:"hello",after:"hellohellohello",selection:range(5,0),text:"hello"))
        XCTAssertFalse(InsertionVerification.confirmed(before:"hi",after:nil,selection:range(0,0),text:"hello"))
        XCTAssertFalse(InsertionVerification.confirmed(before:"hi",after:"hello",selection:nil,text:"hello"))
        XCTAssertFalse(InsertionVerification.confirmed(before:"hi",after:"hello",selection:range(5,0),text:"hello"))
    }
    func testPhysicalShortcutModifiersBlockSyntheticPaste() {
        for flag: CGEventFlags in [.maskControl,.maskAlternate,.maskShift,.maskCommand,.maskSecondaryFn] {
            XCTAssertTrue(InsertionVerification.hasPasteModifiers(flag))
        }
        XCTAssertFalse(InsertionVerification.hasPasteModifiers([]))
        XCTAssertFalse(InsertionVerification.hasPasteModifiers(.maskAlphaShift))
    }
    @MainActor func testOverlappingDictationsRestoreOriginalClipboard() {
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        board.setString("original",forType:.string)
        let clipboard=InsertionClipboard(pasteboard:board)
        let first=clipboard.stage("first"),second=clipboard.stage("second")
        clipboard.restore(first)
        XCTAssertEqual(board.string(forType:.string),"second")
        clipboard.restore(second)
        XCTAssertEqual(board.string(forType:.string),"original")
    }
    @MainActor func testUserCopyDuringLeaseIsPreserved() {
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        board.setString("original",forType:.string)
        let clipboard=InsertionClipboard(pasteboard:board),lease=clipboard.stage("dictation")
        board.clearContents();board.setString("user copy",forType:.string)
        clipboard.restore(lease)
        XCTAssertEqual(board.string(forType:.string),"user copy")
        let next=clipboard.stage("next");clipboard.restore(next)
        XCTAssertEqual(board.string(forType:.string),"user copy")
    }
    @MainActor func testRichClipboardAndEmptyClipboardRestoration() {
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        let rich=Data([1,2,3]);board.setString("original",forType:.string);board.setData(rich,forType:.rtf)
        let clipboard=InsertionClipboard(pasteboard:board),lease=clipboard.stage("dictation")
        clipboard.restore(lease)
        XCTAssertEqual(board.data(forType:.rtf),rich)
        XCTAssertEqual(board.string(forType:.string),"original")
        board.clearContents()
        let empty=clipboard.stage("dictation");clipboard.restore(empty)
        XCTAssertNil(board.string(forType:.string))
    }
}
