import SwiftUI
import FarFlowCore

struct DictationView:View {
    @Bindable var model:AppModel
    @State private var search=""
    @State private var deleteItem:HistoryItem?
    var filtered:[HistoryItem] {model.data.history.filter{search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || $0.raw.localizedCaseInsensitiveContains(search) || $0.appName.localizedCaseInsensitiveContains(search)}}
    var days:[Date] {Set(filtered.map{Calendar.current.startOfDay(for:$0.createdAt)}).sorted(by:>)}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:0) {
                heading.padding(.bottom,18)
                if model.data.preferences.showWelcome {
                    Image("StudioBanner").resizable().scaledToFill().frame(height:174).clipped().clipShape(RoundedRectangle(cornerRadius:10)).accessibilityLabel("Travertine wave in warm architectural light").padding(.bottom,16)
                }
                recordingControls.padding(.bottom,12)
                preferences.padding(.bottom,15)
                Rectangle().fill(FlowTheme.line).frame(height:0.7).padding(.bottom,13)
                HStack(spacing:14) {
                    Text("Recent dictations").font(FlowTheme.body(18,weight:.medium));if model.isDemo {Text("Sample data").font(FlowTheme.body(10)).foregroundStyle(FlowTheme.secondary).padding(.horizontal,8).padding(.vertical,4).background(FlowTheme.line.opacity(0.4),in:Capsule())};Spacer()
                    if model.data.preferences.retention == .off {Text("History is off").font(FlowTheme.body(11)).foregroundStyle(FlowTheme.secondary)}
                    HStack(spacing:8){Image(systemName:"magnifyingglass").font(.system(size:12));TextField("Search dictations…",text:$search).textFieldStyle(.plain).font(FlowTheme.body(12)).accessibilityIdentifier("history.search")}.foregroundStyle(FlowTheme.secondary).padding(.horizontal,11).frame(width:225,height:31).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(FlowTheme.line,lineWidth:0.7))
                    Button{FilePanels.audio{model.importAudio($0)}}label:{Image(systemName:"square.and.arrow.down")}.help("Transcribe an audio file locally").disabled(!model.canRecord || model.state.busy)
                }.padding(.bottom,10)
                if filtered.isEmpty {EmptyFlow(symbol:search.isEmpty ? "waveform":"magnifyingglass",title:search.isEmpty ? "Your words start here":"No matching dictations",detail:search.isEmpty ? "Place your cursor in another app, hold \(model.shortcutTitle), and speak in English or Dutch.":"Try a different word or app name.")}
                else {ForEach(days,id:\.self){day in
                    if !Calendar.current.isDateInToday(day){SectionLabel(title:day.formatted(date:.abbreviated,time:.omitted)).padding(.top,12).padding(.bottom,8)}
                    ForEach(filtered.filter{Calendar.current.isDate($0.createdAt,inSameDayAs:day)}){item in historyRow(item).padding(.bottom,7)}
                }}
            }.padding(.horizontal,32).padding(.top,29).padding(.bottom,20)
        }.safeAreaInset(edge:.bottom,spacing:0) {
            HStack(spacing:7){Image(systemName:"lock").font(.system(size:12));Text("Audio is not saved.").font(FlowTheme.body(11));Spacer();if !model.lastText.isEmpty {Button("View last dictation"){model.showTranscript=true}.font(FlowTheme.body(11))}}.foregroundStyle(FlowTheme.secondary).padding(.horizontal,32).padding(.top,9).padding(.bottom,13).background(FlowTheme.background)
        }.confirmationDialog("Delete this dictation?",isPresented:Binding(get:{deleteItem != nil},set:{if !$0{deleteItem=nil}}),titleVisibility:.visible){Button("Delete",role:.destructive){if let id=deleteItem?.id{model.data.history.removeAll{$0.id==id}};deleteItem=nil}}message:{Text("Both the original and cleaned text will be removed from local history.")}
    }
    private var heading:some View {
        HStack(alignment:.center,spacing:18){
            VStack(alignment:.leading,spacing:5){Text("FAR FLOW").font(FlowTheme.body(9,weight:.medium)).tracking(1.6).foregroundStyle(FlowTheme.secondary);Text("Dictation").font(FlowTheme.body(48));Text("Private English and Dutch dictation on your Mac.").font(FlowTheme.body(14)).foregroundStyle(FlowTheme.secondary)}
            Spacer(minLength:8)
            HStack(alignment:.top,spacing:7){StatusDot(ready:model.speechReady).padding(.top,4);VStack(alignment:.leading,spacing:5){Text("On this Mac").font(FlowTheme.body(13,weight:.medium));Text(model.state.busy ? model.state.title:model.speechReady ? "Ready to use":model.loadingModels ? "Loading models…":"Set up models").font(FlowTheme.body(11)).foregroundStyle(FlowTheme.secondary).lineLimit(2).frame(maxWidth:118,alignment:.leading)}}
            HStack(spacing:8){
                Button{model.data.preferences.appearance = model.data.preferences.appearance == "dark" ? "light":"dark"}label:{Image(systemName:"sun.max").frame(width:18,height:25)}.help("Switch light or dark appearance")
                Button{model.page = .models}label:{Image(systemName:"square.3.layers.3d").frame(width:18,height:25)}.help("Manage local models")
                Menu{Button("Permissions and setup"){model.showOnboarding=true};Button("Settings"){model.page = .settings};Divider();Button("Quit Far Flow"){NSApp.terminate(nil)}}label:{Image(systemName:"ellipsis").frame(width:18,height:25)}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:38,height:30).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(FlowTheme.line,lineWidth:0.7)).tint(FlowTheme.ink)
            }
        }
    }
    private var recordingControls:some View {
        HStack(spacing:23){
            FnKeycap(label:model.shortcutTitle).frame(width:70,height:70)
            Rectangle().fill(FlowTheme.line).frame(width:0.7,height:54)
            VStack(alignment:.leading,spacing:6){Text(model.state.busy ? model.state.title:"Hold \(model.shortcutTitle) to speak").font(FlowTheme.body(23,weight:.medium));Text(model.state == .recording ? (model.handsFree ? "Hands-free · press Fn to stop":"Release Fn to insert."):"Release to insert. Double-tap for hands-free.").font(FlowTheme.body(13)).foregroundStyle(FlowTheme.secondary)}
            Spacer(minLength:5)
            if model.state.busy && model.state != .recording {ProgressView().controlSize(.small);Button("Cancel"){model.cancelRecording()}.disabled(model.state == .inserting)}
            else {Button(model.state == .recording ? "Stop dictation":"Start hands-free"){model.toggleRecording()}.buttonStyle(FlowActionStyle()).disabled(!model.canRecord).accessibilityIdentifier("dictation.record")}
        }.padding(.horizontal,22).padding(.vertical,12).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(FlowTheme.line,lineWidth:0.7))
    }
    private var preferences:some View {
        HStack(spacing:18){
            Text("Language").font(FlowTheme.body(12)).foregroundStyle(FlowTheme.secondary)
            Picker("Dictation language",selection:$model.data.preferences.language){ForEach(DictationLanguage.allCases){Text($0.title).tag($0)}}.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Dictation language").frame(width:295)
            Spacer(minLength:10)
            Rectangle().fill(FlowTheme.line).frame(width:0.7,height:26)
            Text("Cleanup").font(FlowTheme.body(12)).foregroundStyle(FlowTheme.secondary)
            Toggle("Cleanup enabled",isOn:Binding(get:{model.data.preferences.cleanup != .none},set:{model.data.preferences.cleanup=$0 ? .light:.none})).toggleStyle(FlowSwitchStyle()).labelsHidden()
            Picker("Cleanup",selection:$model.data.preferences.cleanup){ForEach(CleanupLevel.allCases){Text($0 == .none ? "No cleanup":"\($0.title) cleanup").tag($0)}}.labelsHidden().frame(width:126)
        }.frame(height:42)
    }
    private func historyRow(_ item:HistoryItem)->some View {
        HStack(alignment:.center,spacing:15){
            Image(systemName:"doc.text").font(.system(size:17,weight:.light)).foregroundStyle(FlowTheme.ink).frame(width:35,height:35).background(FlowTheme.line.opacity(0.32),in:RoundedRectangle(cornerRadius:7))
            Text(item.text).font(FlowTheme.body(13)).lineSpacing(3).lineLimit(2).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
            VStack(alignment:.leading,spacing:5){Text(item.language == "nl" ? "Dutch":item.language == "en" ? "English":item.language.uppercased());Text("\(Calendar.current.isDateInToday(item.createdAt) ? "Today":item.createdAt.formatted(date:.abbreviated,time:.omitted)), \(item.createdAt.formatted(date:.omitted,time:.shortened))").foregroundStyle(FlowTheme.secondary)}.font(FlowTheme.body(11)).frame(width:112,alignment:.leading)
            Button{InsertionService.copy(item.text)}label:{Image(systemName:"document.on.document").font(.system(size:12)).frame(width:13,height:13)}.help("Copy dictation")
            Menu{Button("Copy cleaned text"){InsertionService.copy(item.text)};Button("Copy original"){InsertionService.copy(item.raw)};Button("Compare with original"){model.lastRaw=item.raw;model.lastText=item.text;model.lastStatus=item.outcome;model.showTranscript=true};Divider();Text("\(item.appName) · \(item.wordCount) words · \(item.processingSeconds,specifier:"%.1f")s");Button("Delete",role:.destructive){deleteItem=item}}label:{Image(systemName:"ellipsis").font(.system(size:13))}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:29,height:30).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(FlowTheme.line,lineWidth:0.7)).tint(FlowTheme.ink)
        }.padding(.horizontal,12).padding(.vertical,11).frame(minHeight:59).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(FlowTheme.line,lineWidth:0.7))
    }
}

private struct FnKeycap:View {
    let label:String
    var body:some View {
        ZStack(alignment:.bottomLeading){RoundedRectangle(cornerRadius:13).fill(LinearGradient(colors:[Color(white:0.24),Color(white:0.06)],startPoint:.topLeading,endPoint:.bottomTrailing)).shadow(color:.black.opacity(0.22),radius:6,x:0,y:4);RoundedRectangle(cornerRadius:10).fill(LinearGradient(colors:[Color(white:0.18),Color(white:0.105)],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay(RoundedRectangle(cornerRadius:10).stroke(.white.opacity(0.12),lineWidth:0.7)).padding(5);Text(label).font(FlowTheme.body(14)).foregroundStyle(.white.opacity(0.9)).padding(13)}.accessibilityHidden(true)
    }
}
