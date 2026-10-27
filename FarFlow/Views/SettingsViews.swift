import SwiftUI
import ServiceManagement
import FarFlowCore

struct ModelsView: View {
    @Bindable var model: AppModel
    @State private var removing: ModelManifest?
    var body: some View {
        ScrollView {VStack(alignment:.leading,spacing:25){
            PageHeading(title:"Models",subtitle:"Installed once. Used entirely on this Mac."){Button("Reload models"){Task{await model.warmModels()}}.disabled(model.loadingModels || model.state.busy)}
            ForEach(model.manifests){manifest in
                VStack(alignment:.leading,spacing:18){
                    HStack(alignment:.top){Image(systemName:manifest.id=="parakeet-v3" ? "waveform":"sparkles").font(.system(size:25,weight:.light)).foregroundStyle(FlowTheme.green).frame(width:35);VStack(alignment:.leading,spacing:7){Text(manifest.title).font(.headline);Text(manifest.id=="parakeet-v3" ? "Parakeet v3 · English and Dutch · Core ML":"Qwen3 4B Instruct · 4-bit · MLX").font(.subheadline).foregroundStyle(.secondary);Text("\(ByteCountFormatter.string(fromByteCount:manifest.byteCount,countStyle:.file)) · \(manifest.license)").font(.caption).foregroundStyle(.secondary)};Spacer();Text(model.installedModels.contains(manifest.id) ? "Installed":"Not installed").font(.caption.weight(.medium)).foregroundStyle(model.installedModels.contains(manifest.id) ? FlowTheme.green:.secondary)}
                    if model.modelOperation==manifest.id {ProgressView(value:model.modelProgress[manifest.id] ?? 0);Text("Installing or verifying… \(Int((model.modelProgress[manifest.id] ?? 0)*100))%").font(.caption).foregroundStyle(.secondary)}
                    HStack{
                        if model.installedModels.contains(manifest.id){Button("Verify files"){model.modelAction(manifest,verify:true)};Button("Remove…",role:.destructive){removing=manifest}}
                        else{Button("Download model"){model.modelAction(manifest)}.buttonStyle(FlowActionStyle())}
                        Button("Import folder…"){FilePanels.folder{model.modelAction(manifest,importURL:$0)}}
                        Spacer();Text(String(manifest.revision.prefix(12))).font(.system(size:10,design:.monospaced)).foregroundStyle(.tertiary)
                    }.disabled(model.modelOperation != nil || model.state.busy)
                }.padding(.vertical,15)
                Divider()
            }
            HStack(alignment:.top,spacing:12){Image(systemName:"lock.shield").font(.title2).foregroundStyle(FlowTheme.green);VStack(alignment:.leading,spacing:7){Text("No cloud fallback").font(.headline);Text("Models and tokenizers load from local files. Downloads happen only when you choose Download model. Checksums are verified before installation.").font(.subheadline).foregroundStyle(.secondary)}}.padding(.top,10)
            Button("Show model files in Finder"){NSWorkspace.shared.open(FlowPaths.models)}
            if model.loadingModels{ProgressView(model.modelStatus).controlSize(.small)}
        }.padding(34)}
        .confirmationDialog("Move this model to Trash?",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}}),titleVisibility:.visible){Button("Move to Trash",role:.destructive){if let modelToRemove=removing{model.removeModel(modelToRemove)};removing=nil}}message:{Text("Dictation or AI writing will be unavailable until the model is installed again.")}
    }
}

struct PreferencesView: View {
    @Bindable var model: AppModel
    @State private var loginError=""
    @State private var clearHistory=false
    @State private var importing: URL?
    @State private var showNotices=false
    var body: some View {
        ScrollView {VStack(alignment:.leading,spacing:25){
            PageHeading(title:"Settings",subtitle:"Make Far Flow work your way."){EmptyView()}
            SectionLabel(title:"Dictation")
            setting("Hold-to-talk shortcut",detail:"Double-tap Fn for hands-free. Control–Option–Return also works."){
                Picker("Shortcut",selection:$model.data.preferences.shortcut){Text("Control–Option–Space").tag("controlOptionSpace");Text("Fn (Globe)").tag("fn")}.labelsHidden().frame(width:215)
            }
            if model.data.preferences.shortcut=="fn"{Text("Set System Settings → Keyboard → Press 🌐 key to → Do Nothing. Keep Fn assigned to one dictation app.").font(.caption).foregroundStyle(.secondary)}
            setting("Microphone",detail:"The selected input is used only by Far Flow."){
                Picker("Microphone",selection:$model.data.preferences.inputDeviceID){Text("System default").tag(UInt32(0));ForEach(model.devices){Text($0.name).tag($0.id)}}.labelsHidden().frame(width:215)
            }
            setting("Language",detail:"Auto keeps English, Dutch, or mixed speech."){Picker("Language",selection:$model.data.preferences.language){ForEach(DictationLanguage.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:215)}
            Toggle("Local AI for deeper writing",isOn:$model.data.preferences.useLocalAI).onChange(of:model.data.preferences.useLocalAI){_,enabled in Task{if enabled {await model.warmModels()}else{await model.writing.unload();model.writingReady=false}}}
            Text("Light is the fast default. Medium and custom app styles use local AI when enabled. Transforms use the writing model when requested.").font(.caption).foregroundStyle(.secondary)
            Divider()
            SectionLabel(title:"Permissions")
            permission("Microphone",ready:model.microphoneGranted,detail:"Hear your speech while recording",action:model.requestMicrophone)
            permission("Accessibility",ready:model.accessibilityGranted,detail:"Insert words into other apps",action:model.requestAccessibility)
            HStack{Image(systemName:model.hotkeyReady ? "checkmark.circle.fill":"circle").foregroundStyle(model.hotkeyReady ? FlowTheme.green:.secondary);Text(model.hotkeyReady ? "Global shortcut active":"Global shortcut starts after Accessibility is granted").font(.subheadline);Spacer()}
            Divider()
            SectionLabel(title:"Local data")
            setting("Keep dictation history",detail:"Applies to original and cleaned transcripts."){Picker("Retention",selection:$model.data.preferences.retention){ForEach(HistoryRetention.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:215)}
            Text("Audio is processed in memory and discarded. History is stored under your macOS account; it is not separately encrypted by Far Flow.").font(.caption).foregroundStyle(.secondary)
            HStack{Button("Export data…"){FilePanels.save(name:"Far Flow Backup.json"){model.exportData(to:$0)}};Button("Import backup…"){FilePanels.openJSON{importing=$0}};Button("Show data folder"){model.revealData()};Spacer();Button("Clear history…",role:.destructive){clearHistory=true}.disabled(model.data.history.isEmpty)}
            Divider()
            SectionLabel(title:"App")
            Text("Closing the main window quits Far Flow and unloads its models. Minimize the window to keep Fn and the floating bar available.").font(.caption).foregroundStyle(.secondary)
            Toggle("Dictation sounds",isOn:$model.data.preferences.sounds)
            Toggle("Pause media while dictating",isOn:Binding(get:{model.data.preferences.pauseMediaDuringDictation ?? true},set:{model.data.preferences.pauseMediaDuringDictation=$0}))
            Text("\(model.mediaStatus). Playback resumes when recording stops, if Far Flow paused it.").font(.caption).foregroundStyle(.secondary)
            Toggle("Show Far Flow in Dock",isOn:$model.data.preferences.showDock)
            Toggle("Always show the recording bar",isOn:$model.data.preferences.alwaysShowBar)
            HStack{Text("Drag the small recording bar to any screen edge. Its position is remembered.").font(.caption).foregroundStyle(.secondary);Spacer();Button("Reset bar position"){model.resetRecordingBarPosition()}}
            Toggle("Show banner image",isOn:$model.data.preferences.showWelcome)
            Toggle("Open at login",isOn:Binding(get:{SMAppService.mainApp.status == .enabled},set:{enabled in do{if enabled{try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()}}catch{loginError=error.localizedDescription}}))
            if !loginError.isEmpty{Text(loginError).font(.caption).foregroundStyle(.red)}
            setting("Appearance",detail:"Light, dark, or follow macOS."){Picker("Appearance",selection:$model.data.preferences.appearance){Text("System").tag("system");Text("Light").tag("light");Text("Dark").tag("dark")}.labelsHidden().frame(width:215)}
            Divider();HStack{Text("Far Flow \(FarFlowVersion.value) · Native macOS · English + Nederlands").font(.caption).foregroundStyle(.secondary);Spacer();Button("Open-source notices"){showNotices=true}.font(.caption)}
        }.padding(34)}
        .confirmationDialog("Clear all local dictation history?",isPresented:$clearHistory,titleVisibility:.visible){Button("Clear history",role:.destructive){model.data.history=[]}}
        .confirmationDialog("Restore this backup?",isPresented:Binding(get:{importing != nil},set:{if !$0{importing=nil}}),titleVisibility:.visible){Button("Restore backup"){if let url=importing{let backup=FlowPaths.root.appendingPathComponent("Before Import \(Int(Date().timeIntervalSince1970)).json");model.exportData(to:backup);model.importData(from:url)};importing=nil}}message:{Text("Your current data will first be exported to the local data folder. The selected backup will replace notes, history, dictionary, snippets, styles, and preferences.")}
        .sheet(isPresented:$showNotices){VStack(alignment:.leading,spacing:18){HStack{Text("Open-source notices").font(.title2);Spacer();Button("Done"){showNotices=false}};ScrollView{Text(notices).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}.padding(28).frame(width:650,height:530)}
    }
    private func setting<Content:View>(_ title:String,detail:String,@ViewBuilder content:()->Content)->some View{HStack(spacing:20){VStack(alignment:.leading,spacing:6){Text(title).font(.subheadline.weight(.medium));Text(detail).font(.caption).foregroundStyle(.secondary)};Spacer();content()}}
    private func permission(_ title:String,ready:Bool,detail:String,action:@escaping()->Void)->some View{HStack{Image(systemName:ready ? "checkmark.circle.fill":"circle").foregroundStyle(ready ? FlowTheme.green:.secondary);VStack(alignment:.leading,spacing:4){Text(title).font(.subheadline);Text(detail).font(.caption).foregroundStyle(.secondary)};Spacer();Button(ready ? "Open settings":"Allow…",action:action)}}
    private var notices: String {guard let url=Bundle.main.url(forResource:"ThirdPartyNotices",withExtension:"txt")else{return "Notices are included in docs/THIRD-PARTY-NOTICES.txt in the Xcode source project."};return (try? String(contentsOf:url,encoding:.utf8)) ?? "Could not read the notices file."}
}

struct SetupView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:24){
            HStack(spacing:13){Image("AppMark").resizable().frame(width:45,height:45).clipShape(RoundedRectangle(cornerRadius:12));VStack(alignment:.leading,spacing:5){Text("Welcome to Far Flow").font(.system(size:26,weight:.medium,design:.serif));Text("Your voice. At home.").foregroundStyle(.secondary)}}
            Text("Dictate in English or Dutch. Speech and cleanup run on your Mac. Let’s prepare the microphone and keyboard shortcut.").font(.subheadline).foregroundStyle(.secondary)
            setupRow("Microphone",detail:"Record only while you dictate",ready:model.microphoneGranted,action:model.requestMicrophone)
            setupRow("Accessibility",detail:"Insert text at your cursor in other apps",ready:model.accessibilityGranted,action:model.requestAccessibility)
            HStack(spacing:12){Image(systemName:"keyboard").foregroundStyle(FlowTheme.green).font(.title3);VStack(alignment:.leading,spacing:5){Text("Your shortcut").font(.headline);Text("Uses the Accessibility permission above").font(.caption).foregroundStyle(.secondary)};Spacer();Picker("Shortcut",selection:$model.data.preferences.shortcut){Text("Fn (Globe)").tag("fn");Text("Control–Option–Space").tag("controlOptionSpace")}.labelsHidden().frame(width:180)}
            Divider()
            HStack{StatusDot(ready:model.speechReady);Text(model.modelStatus).font(.subheadline);Spacer();if !model.installedModels.contains("parakeet-v3"){Button("Set up models"){model.page = .models;model.showOnboarding=false}}}
            Picker("Keep local transcripts",selection:$model.data.preferences.retention){ForEach(HistoryRetention.allCases){Text($0.title).tag($0)}}
            Text("Audio is not saved. You can change transcript retention in Settings.").font(.caption).foregroundStyle(.secondary)
            HStack{Button("Set up later"){model.showOnboarding=false};Spacer();Button("Start using Far Flow"){model.data.preferences.onboardingComplete=true;model.showOnboarding=false}.buttonStyle(FlowActionStyle()).disabled(!model.microphoneGranted || !model.speechReady)}
        }.padding(34).frame(width:550)
    }
    private func setupRow(_ title:String,detail:String,ready:Bool,action:@escaping()->Void)->some View{HStack(spacing:12){Image(systemName:ready ? "checkmark.circle.fill":"circle").foregroundStyle(ready ? FlowTheme.green:.secondary).font(.title3);VStack(alignment:.leading,spacing:5){Text(title).font(.headline);Text(detail).font(.caption).foregroundStyle(.secondary)};Spacer();Button(ready ? "Granted":"Allow…",action:action).disabled(ready)}}
}
