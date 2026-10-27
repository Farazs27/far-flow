import SwiftUI
import FarFlowCore
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:17) {
                    FlowMark().fill(FlowTheme.sidebarInk).frame(width:30,height:34)
                    Text("FAR FLOW").font(FlowTheme.body(13,weight:.medium)).tracking(3.3).foregroundStyle(FlowTheme.sidebarInk)
                }.padding(.horizontal,25).padding(.top,58).padding(.bottom,30)
                VStack(spacing:5) { ForEach(FlowPage.allCases) { page in sidebarRow(page) } }
                Spacer(minLength:20)
            }.frame(width:205).background(FlowTheme.sidebar)
            Group {
                switch model.page {
                case .dictation: DictationView(model:model)
                case .dictionary: DictionaryView(model:model)
                case .snippets: SnippetsView(model:model)
                case .styles: StylesView(model:model)
                case .transforms: TransformsView(model:model)
                case .scratchpad: ScratchpadView(model:model)
                case .insights: InsightsView(model:model)
                case .models: ModelsView(model:model)
                case .settings: PreferencesView(model:model)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(FlowTheme.background)
        }.font(FlowTheme.body()).foregroundStyle(FlowTheme.ink).buttonStyle(FlowUtilityStyle())
        .frame(minWidth:1040,minHeight:760).tint(FlowTheme.green)
        .ignoresSafeArea(.container,edges:.top)
        .background(MainWindowCloseObserver())
        .sheet(isPresented:$model.showOnboarding) { SetupView(model:model) }
        .sheet(isPresented:$model.showTranscript) { TranscriptSheet(model:model) }
        .alert("Far Flow",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) { Button("OK") { model.error=nil } } message: { Text(model.error ?? "") }
        .onChange(of:model.data.preferences) { _,_ in model.preferencesChanged() }
        .onReceive(NotificationCenter.default.publisher(for:.openFarFlowHub)) { _ in openWindow(id:"hub") }
    }
    private func sidebarRow(_ page:FlowPage)->some View {
        Button {model.page=page} label:{HStack(spacing:14){Image(systemName:page.symbol).font(.system(size:16,weight:.regular)).frame(width:20);Text(page.rawValue).font(FlowTheme.body(13));Spacer();if page == .models && !model.speechReady {Circle().fill(.orange).frame(width:5,height:5)}}.foregroundStyle(FlowTheme.sidebarInk).padding(.horizontal,16).frame(height:43).background(model.page==page ? Color(red:0.22,green:0.21,blue:0.18):.clear,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).padding(.horizontal,12).accessibilityIdentifier("nav.\(page.rawValue.lowercased())")
    }
}

/// The floating panel is another window, so observe the dashboard explicitly.
struct MainWindowCloseObserver:NSViewRepresentable {
    func makeNSView(context:Context)->CloseObservingView {CloseObservingView()}
    func updateNSView(_ view:CloseObservingView,context:Context) {}
    final class CloseObservingView:NSView {
        private var observer:NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {NotificationCenter.default.removeObserver(observer);self.observer=nil}
            guard let window else{return}
            observer=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main){_ in NSApp.terminate(nil)}
        }
        deinit {if let observer {NotificationCenter.default.removeObserver(observer)}}
    }
}

struct TranscriptSheet: View {
    @Bindable var model: AppModel
    @State private var original=false
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text("Your dictation").font(.title2.weight(.semibold)); Spacer(); Button("Done") { model.showTranscript=false }.keyboardShortcut(.cancelAction) }
            Text(model.lastStatus).font(.subheadline).foregroundStyle(.secondary)
            Picker("Version",selection:$original) { Text("Cleaned").tag(false); Text("Original").tag(true) }.pickerStyle(.segmented)
            ScrollView { Text(original ? model.lastRaw : model.lastText).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(18) }.frame(minHeight:180,maxHeight:350).background(.quaternary.opacity(0.4),in:RoundedRectangle(cornerRadius:10))
            HStack { Text("Processed entirely on this Mac").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Copy text") { InsertionService.copy(original ? model.lastRaw:model.lastText) }.buttonStyle(FlowActionStyle()) }
        }.padding(30).frame(width:590)
    }
}

enum FilePanels {
    @MainActor static func audio(_ completion: (URL)->Void) { let p=NSOpenPanel();p.allowedContentTypes=[.audio];p.canChooseDirectories=false;p.allowsMultipleSelection=false;if p.runModal() == .OK,let u=p.url {completion(u)} }
    @MainActor static func folder(_ completion: (URL)->Void) { let p=NSOpenPanel();p.canChooseDirectories=true;p.canChooseFiles=false;p.allowsMultipleSelection=false;if p.runModal() == .OK,let u=p.url {completion(u)} }
    @MainActor static func save(name:String,type:UTType = .json,_ completion:(URL)->Void) { let p=NSSavePanel();p.nameFieldStringValue=name;p.allowedContentTypes=[type];if p.runModal() == .OK,let u=p.url {completion(u)} }
    @MainActor static func openJSON(_ completion:(URL)->Void) { let p=NSOpenPanel();p.allowedContentTypes=[.json];p.allowsMultipleSelection=false;if p.runModal() == .OK,let u=p.url {completion(u)} }
}
