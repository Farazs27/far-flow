import SwiftUI
import FarFlowCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var shuttingDown=false
    private var shutdownComplete=false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if shutdownComplete{return .terminateNow}
        if shuttingDown{return .terminateLater}
        shuttingDown=true
        MainActor.assumeIsolated{model?.terminate()}
        Task { @MainActor in
            await model?.unloadForTermination()
            guard !shutdownComplete else{return};shutdownComplete=true;sender.reply(toApplicationShouldTerminate:true)
        }
        // Process exit releases any model still completing a noncancelable Core ML load.
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in
            guard let self,!self.shutdownComplete else{return}
            self.shutdownComplete=true;sender.reply(toApplicationShouldTerminate:true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { model?.terminate() } }
}

@main struct FarFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model=AppModel()
    @State private var launched=false
    var body: some Scene {
        WindowGroup("Far Flow",id:"hub") {
            RootView(model:model).onAppear { if !launched { launched=true; delegate.model=model; model.launch() } }
        }
        .defaultSize(width:1160,height:820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("New Scratchpad Note") { model.data.notes.insert(ScratchNote(),at:0); model.page = .scratchpad }.keyboardShortcut("n")
            }
            CommandMenu("Dictation") {
                Button(model.state == .recording ? "Stop Dictation" : "Start Dictation") { model.toggleRecording() }.keyboardShortcut("d",modifiers:[.command,.shift])
                Button("Cancel Dictation") { model.cancelRecording() }.disabled(!model.state.busy)
            }
            CommandGroup(replacing:.appSettings) { Button("Settings…") { model.page = .settings; model.openHub() }.keyboardShortcut(",") }
        }
        MenuBarExtra("Far Flow",systemImage:model.state == .recording ? "mic.fill" : "waveform") { MenuContents(model:model) }
    }
}

struct MenuContents: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Far Flow · On this Mac")
        Text(model.state.busy ? model.state.title : model.modelStatus)
        Divider()
        Button(model.state == .recording ? "Stop Dictation" : "Start Hands-Free Dictation") { model.toggleRecording() }.disabled(!model.canRecord && model.state == .idle)
        Button("Cancel") { model.cancelRecording() }.disabled(!model.state.busy)
        Button("Transform Selection") { model.captureSelection(); openWindow(id:"hub"); NSApp.activate(ignoringOtherApps:true) }
        if !model.lastText.isEmpty { Button("Copy Last Dictation") { InsertionService.copy(model.lastText) } }
        Divider()
        Button("Open Far Flow") { openWindow(id:"hub"); NSApp.activate(ignoringOtherApps:true) }
        Button("Settings…") { model.page = .settings; openWindow(id:"hub"); NSApp.activate(ignoringOtherApps:true) }
        Divider()
        Text("Hold \(model.shortcutTitle) to speak")
        Text("⌃ ⌥ Return for hands-free")
        Divider()
        Button("Quit Far Flow") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
