import AppKit
import ApplicationServices
import FarFlowCore

@MainActor final class ShortcutService {
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onToggle: (() -> Void)?
    var onLock: (() -> Void)?
    var onCancel: (() -> Void)?
    var shortcut="controlOptionSpace"
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var held=false
    private var fnHeld=false
    private var toggleHeld=false
    private var fnGesture=FnGesture()
    private var pendingFnStop: DispatchWorkItem?
    var available: Bool { tap != nil }

    func start() {
        guard tap==nil,AXIsProcessTrusted() else { return }
        let mask=(1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _,type,event,context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let service=Unmanaged<ShortcutService>.fromOpaque(context).takeUnretainedValue()
            let consume=MainActor.assumeIsolated { service.handle(type,event) }
            return consume ? nil:Unmanaged.passUnretained(event)
        }
        // An active tap is authorized by Accessibility. No separate listen-only
        // Input Monitoring grant is needed. Only the chosen dictation chord is consumed.
        tap=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:CGEventMask(mask),callback:callback,userInfo:Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)
        CGEvent.tapEnable(tap:tap,enable:true)
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap:tap,enable:false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        tap=nil; source=nil; held=false; fnHeld=false;toggleHeld=false;resetGesture()
    }
    func resetGesture(){pendingFnStop?.cancel();pendingFnStop=nil;fnGesture.reset()}
    func lockRecording(){pendingFnStop?.cancel();pendingFnStop=nil;fnGesture.lockRecording()}
    private func handle(_ type: CGEventType,_ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if let tap { CGEvent.tapEnable(tap:tap,enable:true) }; return false }
        let code=event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, code == 53 {resetGesture();enqueue(onCancel);return false}
        let flags=event.flags
        let modifiers=flags.contains(.maskControl) && flags.contains(.maskAlternate) && !flags.contains(.maskCommand)
        if type == .keyDown, modifiers, code == 36 {if !toggleHeld{toggleHeld=true;resetGesture();enqueue(onToggle)};return true}
        if type == .keyUp, code == 36,toggleHeld {toggleHeld=false;return true}
        if shortcut == "fn", type == .flagsChanged {
            let pressed=flags.contains(.maskSecondaryFn)
            if pressed && !fnHeld {fnHeld=true;pendingFnStop?.cancel();perform(fnGesture.press(at:ProcessInfo.processInfo.systemUptime));return true}
            else if !pressed && fnHeld {
                fnHeld=false;perform(fnGesture.release(at:ProcessInfo.processInfo.systemUptime))
                if let deadline=fnGesture.pendingStopDeadline {
                    let work=DispatchWorkItem{[weak self] in guard let self else{return};self.perform(self.fnGesture.expire(at:ProcessInfo.processInfo.systemUptime))}
                    pendingFnStop=work;DispatchQueue.main.asyncAfter(deadline:.now()+max(0,deadline-ProcessInfo.processInfo.systemUptime),execute:work)
                }
                return true
            }
        } else if shortcut == "fn",fnHeld,type == .keyDown,!fnGesture.isLocked {
            // Fn + arrows/function keys retain their normal keyboard behavior.
            fnHeld=false;resetGesture();enqueue(onCancel)
        } else if shortcut != "fn" {
            if type == .keyDown, modifiers, code == 49 {if !held{held=true;enqueue(onStart)};return true}
            else if type == .keyUp, code == 49, held { held=false; enqueue(onStop); return true }
            else if type == .flagsChanged, held, !modifiers { held=false; enqueue(onStop) }
        }
        return false
    }
    private func perform(_ actions:[FnGesture.Action]){for action in actions{switch action{case .start:enqueue(onStart);case .stop:enqueue(onStop);case .lock:enqueue(onLock)}}}
    private func enqueue(_ action: (() -> Void)?) {guard let action else{return};DispatchQueue.main.async(execute:action)}
}
