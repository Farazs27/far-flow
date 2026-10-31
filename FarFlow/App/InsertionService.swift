import AppKit
import ApplicationServices

struct InsertionTarget {
    let pid: pid_t
    let appName: String
    let bundleID: String
    let element: AXUIElement
    let selectedText: String?
    let selection: CFTypeRef?
    let secure: Bool
}

@MainActor enum InsertionService {
    static func value(_ element: AXUIElement,_ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,attribute as CFString,&result) == .success else { return nil }
        return result
    }
    static func capture(pid: pid_t? = nil) -> InsertionTarget? {
        let app: NSRunningApplication?
        if let pid { app=NSRunningApplication(processIdentifier:pid) }
        else { app=NSWorkspace.shared.frontmostApplication }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root=AXUIElementCreateApplication(app.processIdentifier)
        if InsertionVerification.prefersPaste(bundleID:app.bundleIdentifier ?? "") {
            // Electron lazily exposes its accessibility tree to assistive apps.
            _ = AXUIElementSetAttributeValue(root,"AXManualAccessibility" as CFString,kCFBooleanTrue)
        }
        guard let item=value(root,kAXFocusedUIElementAttribute), CFGetTypeID(item)==AXUIElementGetTypeID() else { return nil }
        let element=item as! AXUIElement
        let subrole=value(element,kAXSubroleAttribute) as? String ?? ""
        let role=value(element,kAXRoleAttribute) as? String ?? ""
        let secure=subrole=="AXSecureTextField" || role=="AXSecureTextField" || (value(element,"AXProtectedContent") as? Bool)==true
        return InsertionTarget(pid:app.processIdentifier,appName:app.localizedName ?? "App",bundleID:app.bundleIdentifier ?? "",element:element,selectedText:secure ? nil:value(element,kAXSelectedTextAttribute) as? String,selection:secure ? nil:value(element,kAXSelectedTextRangeAttribute),secure:secure)
    }
    static func targetUnchanged(_ target: InsertionTarget, requireSelection: Bool = true) -> Bool {
        guard let current=capture(), current.pid==target.pid, CFEqual(current.element,target.element), !current.secure else { return false }
        if requireSelection, let before=target.selection {
            guard let now=current.selection, CFEqual(before,now) else { return false }
        }
        return true
    }
    private static let clipboard = InsertionClipboard(pasteboard: .general)

    static func insert(_ text: String, into target: InsertionTarget) async -> String {
        guard AXIsProcessTrusted() else { return "Accessibility required · copy text" }
        guard !target.secure else { return "Secure field · insertion blocked" }
        let terminals=["com.apple.Terminal","com.googlecode.iterm2","com.mitchellh.ghostty","dev.warp.Warp-Stable"]
        if terminals.contains(target.bundleID),text.contains(where:{$0=="\n" || $0=="\r"}) {return "Multi-line terminal text · review and copy"}
        // Physical modifiers can combine with synthetic Cmd-V in editors.
        for _ in 0..<40 {
            guard !Task.isCancelled else { return "Canceled · copy text" }
            guard targetUnchanged(target) else { return "Focus changed · copy text" }
            if !InsertionVerification.hasPasteModifiers(CGEventSource.flagsState(.combinedSessionState)) { break }
            do { try await Task.sleep(for:.milliseconds(25)) }
            catch { return "Canceled · copy text" }
        }
        guard !InsertionVerification.hasPasteModifiers(CGEventSource.flagsState(.combinedSessionState)) else { return "Release shortcut keys · copy text" }
        guard targetUnchanged(target) else { return "Focus changed · copy text" }
        let originalValue=value(target.element,kAXValueAttribute) as? String
        var settable: DarwinBoolean=false
        if !InsertionVerification.prefersPaste(bundleID:target.bundleID),originalValue != nil,AXUIElementIsAttributeSettable(target.element,kAXSelectedTextAttribute as CFString,&settable) == .success, settable.boolValue {
            let result=AXUIElementSetAttributeValue(target.element,kAXSelectedTextAttribute as CFString,text as CFString)
            let after=value(target.element,kAXValueAttribute) as? String
            // An accepted AX write can be asynchronous. Do not mutate twice.
            if result == .success || after != originalValue {
                return InsertionVerification.confirmed(before:originalValue,after:after,selection:target.selection,text:text) ? "Inserted" : "Insertion requested · check field"
            }
        }
        guard targetUnchanged(target) else { return "Focus changed · copy text" }
        let source=CGEventSource(stateID:.combinedSessionState)
        let down=CGEvent(keyboardEventSource:source,virtualKey:9,keyDown:true), up=CGEvent(keyboardEventSource:source,virtualKey:9,keyDown:false)
        guard let down,let up else { return "Paste unavailable · copy text" }
        let lease=clipboard.stage(text)
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap)
        try? await Task.sleep(for:.milliseconds(150))
        let after=value(target.element,kAXValueAttribute) as? String
        Task{@MainActor in try? await Task.sleep(for:.milliseconds(650));clipboard.restore(lease)}
        return InsertionVerification.confirmed(before:originalValue,after:after,selection:target.selection,text:text) ? "Inserted" : "Paste requested · check field"
    }
    static func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string) }

    /// Undo only when the inserted span is still present and the caret has not moved.
    static func undoTransform(target: InsertionTarget, inserted: String) async -> String {
        guard let selected=target.selection, CFGetTypeID(selected)==AXValueGetTypeID(), let original=target.selectedText else { return "Use Undo in the destination app, or copy the original text." }
        var before=CFRange(); guard AXValueGetValue(selected as! AXValue,.cfRange,&before) else { return "The original range is unavailable." }
        guard let current=capture(), current.pid==target.pid, CFEqual(current.element,target.element), !current.secure,
              let rangeValue=current.selection, CFGetTypeID(rangeValue)==AXValueGetTypeID(), let full=value(current.element,kAXValueAttribute) as? String else { return "The destination changed. Copy the original text to restore it." }
        var caret=CFRange();guard AXValueGetValue(rangeValue as! AXValue,.cfRange,&caret),caret.length==0,caret.location==before.location+inserted.utf16.count else { return "The cursor moved. Use Undo in the destination app." }
        let range=NSRange(location:before.location,length:inserted.utf16.count)
        guard let swiftRange=Range(range,in:full),String(full[swiftRange])==inserted else { return "The inserted text changed. Use Undo in the destination app." }
        var replacement=CFRange(location:before.location,length:inserted.utf16.count)
        guard let axRange=AXValueCreate(.cfRange,&replacement),AXUIElementSetAttributeValue(current.element,kAXSelectedTextRangeAttribute as CFString,axRange) == .success,
              let focused=capture() else { return "This app does not support restoring the selection. Copy the original text." }
        return await insert(original,into:focused)
    }
}

/// Verify the exact UTF-16 replacement, including repeated text.
enum InsertionVerification {
    /// Web editors maintain their own document state; AX setters may acknowledge
    /// writes without updating that state. A real paste reaches the editor handler.
    static func prefersPaste(bundleID: String) -> Bool {
        ["com.openai.codex","com.openai.chat","com.google.Chrome","com.microsoft.VSCode",
         "com.todesktop.230313mzl4w4u92","com.google.antigravity","com.anthropic.claudefordesktop",
         "com.microsoft.edgemac","com.brave.Browser","org.mozilla.firefox","com.apple.Safari"].contains(bundleID)
    }

    static func hasPasteModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskShift,.maskSecondaryFn]).isEmpty
    }
    static func confirmed(before: String?, after: String?, selection: CFTypeRef?, text: String) -> Bool {
        guard let before, let after, let selection, CFGetTypeID(selection)==AXValueGetTypeID() else { return false }
        var range=CFRange()
        guard AXValueGetValue(selection as! AXValue,.cfRange,&range),range.location>=0,range.length>=0,
              range.location <= before.utf16.count,range.length <= before.utf16.count-range.location else { return false }
        let expected=(before as NSString).replacingCharacters(in:NSRange(location:range.location,length:range.length),with:text)
        return after==expected
    }
}

/// Serialize clipboard leases; user clipboard changes always win.
@MainActor final class InsertionClipboard {
    private let pasteboard: NSPasteboard
    private var pending: (id: UUID, count: Int, items: [[(NSPasteboard.PasteboardType,Data)]])?
    init(pasteboard: NSPasteboard) { self.pasteboard=pasteboard }
    func stage(_ text: String) -> UUID {
        if let pending { restore(pending.id) }
        let previous=pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
        pasteboard.clearContents();pasteboard.setString(text,forType:.string)
        let id=UUID();pending=(id,pasteboard.changeCount,previous);return id
    }
    func restore(_ id: UUID) {
        guard let lease=pending,lease.id==id else { return }
        pending=nil
        guard pasteboard.changeCount==lease.count else { return }
        pasteboard.clearContents()
        let items=lease.items.map { values in
            let item=NSPasteboardItem()
            for (type,data) in values { item.setData(data,forType:type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
