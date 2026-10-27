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
        let app=pid.flatMap { NSRunningApplication(processIdentifier:$0) } ?? NSWorkspace.shared.frontmostApplication
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root=AXUIElementCreateApplication(app.processIdentifier)
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
    static func insert(_ text: String, into target: InsertionTarget) async -> String {
        guard AXIsProcessTrusted() else { return "Accessibility required · copy text" }
        guard !target.secure else { return "Secure field · insertion blocked" }
        let terminals=["com.apple.Terminal","com.googlecode.iterm2","com.mitchellh.ghostty","dev.warp.Warp-Stable"]
        if terminals.contains(target.bundleID),text.contains(where:{$0=="\n" || $0=="\r"}) {return "Multi-line terminal text · review and copy"}
        guard targetUnchanged(target) else { return "Focus changed · copy text" }
        let originalValue=value(target.element,kAXValueAttribute) as? String
        var settable: DarwinBoolean=false
        if let before=originalValue,AXUIElementIsAttributeSettable(target.element,kAXSelectedTextAttribute as CFString,&settable) == .success, settable.boolValue {
            if AXUIElementSetAttributeValue(target.element,kAXSelectedTextAttribute as CFString,text as CFString) == .success {
                if let after=value(target.element,kAXValueAttribute) as? String, after != before, after.contains(text) { return "Inserted" }
                if target.selectedText==text{return "Inserted"}
                if let after=value(target.element,kAXValueAttribute) as? String,after != before{return "Insertion requested · check field"}
            }
        }
        let pasteboard=NSPasteboard.general
        let previous=pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
        pasteboard.clearContents(); pasteboard.setString(text,forType:.string)
        let ownedCount=pasteboard.changeCount
        guard targetUnchanged(target) else { restore(previous,ownedCount:ownedCount); return "Focus changed · copy text" }
        let source=CGEventSource(stateID:.combinedSessionState)
        let down=CGEvent(keyboardEventSource:source,virtualKey:9,keyDown:true), up=CGEvent(keyboardEventSource:source,virtualKey:9,keyDown:false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap:.cghidEventTap); up?.post(tap:.cghidEventTap)
        try? await Task.sleep(for:.milliseconds(150))
        let after=value(target.element,kAXValueAttribute) as? String
        // Let slower editors finish reading the pasteboard without delaying completion.
        Task{@MainActor in try? await Task.sleep(for:.milliseconds(650));restore(previous,ownedCount:ownedCount)}
        return after?.contains(text) == true && after != originalValue ? "Inserted" : "Paste requested · check field"
    }
    private static func restore(_ items: [[(NSPasteboard.PasteboardType,Data)]], ownedCount: Int) {
        let pasteboard=NSPasteboard.general
        guard pasteboard.changeCount==ownedCount else { return }
        pasteboard.clearContents()
        let restored=items.map { values in let item=NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
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
