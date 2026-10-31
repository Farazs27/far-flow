import SwiftUI
import Charts
import FarFlowCore

struct TransformsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            PageHeading(title:"Transforms",subtitle:"Review a rewrite before you use it. Everything runs locally.") { Button("Capture selection") {model.captureSelection()} }
            HStack {
                Picker("Transform",selection:$model.transformKind){ForEach(TransformKind.allCases){Text($0.title).tag($0)}}.frame(width:250)
                Spacer()
                if model.transforming {ProgressView().controlSize(.small)}
                Button("Transform text",systemImage:"sparkles"){model.runTransform()}.buttonStyle(FlowActionStyle()).disabled(model.meeting.busy || model.state.busy || model.transforming || model.transformInput.isEmpty || !model.installedModels.contains("qwen-cleanup"))
            }
            HStack(alignment:.top,spacing:18) {
                VStack(alignment:.leading,spacing:10){SectionLabel(title:"Original");TextEditor(text:$model.transformInput).font(.system(size:14)).scrollContentBackground(.hidden).padding(14).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.primary.opacity(0.08))).accessibilityIdentifier("transform.input")}
                VStack(alignment:.leading,spacing:10){SectionLabel(title:"Preview");TextEditor(text:$model.transformOutput).font(.system(size:14)).scrollContentBackground(.hidden).padding(14).background(.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.primary.opacity(0.08))).accessibilityIdentifier("transform.output")}
            }
            HStack {
                Text(model.transformTarget == nil ? "Paste text here, or select text in another app and use the Far Flow menu bar.":"Original selection: \(model.transformTarget?.appName ?? "App")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy result"){InsertionService.copy(model.transformOutput)}.disabled(model.transformOutput.isEmpty)
                if model.transformUndoTarget != nil {Button("Undo replacement"){model.undoTransform()}}
                if model.transformTarget != nil {Button("Replace selection"){model.applyTransform()}.disabled(model.transformOutput.isEmpty || model.transforming)}
            }
            if !model.installedModels.contains("qwen-cleanup") { Button("Install the local writing model"){model.page = .models}.font(.caption) }
        }.padding(34)
        .onChange(of:model.transformInput){_,value in if let target=model.transformTarget,value != target.selectedText {model.transformTarget=nil}}
    }
}

struct ScratchpadView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var deleting: ScratchNote?
    private var notes: [ScratchNote] {
        model.data.notes.filter {
            search.isEmpty || $0.title.localizedStandardContains(search) || $0.text.localizedStandardContains(search)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "Notes", subtitle: "Write or dictate. Your notes stay on this Mac.") {
                Button("New note", systemImage: "plus") { search=""; model.createNote() }
                    .buttonStyle(FlowActionStyle()).accessibilityIdentifier("notes.new")
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search notes", text: $search).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("notes.search").padding(10)
                    if notes.isEmpty {
                        Text(search.isEmpty ? "No notes yet" : "No matching notes")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(notes) { note in
                                Button { model.data.preferences.selectedNoteID=note.id } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(note.title.isEmpty ? "Untitled note" : note.title)
                                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                                        Text(note.text.isEmpty ? "Empty note" : note.text)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        .background(model.selectedNote?.id == note.id ? FlowTheme.green.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityIdentifier("notes.row.\(note.id)")
                            }
                        }.padding(6)
                    }
                }.frame(width: 220)
                Divider()
                if let note=model.selectedNote {
                    noteEditor(note).id(note.id)
                } else {
                    EmptyFlow(symbol: "square.and.pencil", title: "Room to think", detail: "Create a note, then write or dictate. Notes are kept until you delete them.")
                }
            }.frame(maxHeight: .infinity).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
        }.padding(34)
        .onChange(of: model.selectedNote?.id) { _,_ in search="" }
        .confirmationDialog("Delete this note?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting=nil } }), titleVisibility: .visible) {
            Button("Delete note", role: .destructive) {
                if let note=deleting { model.data.deleteNote(id: note.id) }
                deleting=nil
            }
        } message: { Text("This removes the note from this Mac. Export a copy first if you want to keep it.") }
    }
    private func noteEditor(_ note: ScratchNote) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Untitled note", text: Binding(
                get: { model.data.notes.first { $0.id == note.id }?.title ?? "" },
                set: { model.data.updateNote(id: note.id, title: $0) }
            )).font(.title2.weight(.medium)).textFieldStyle(.plain).accessibilityIdentifier("notes.title")
            HStack {
                Text(model.saveError == nil ? "Saved on this Mac" : "Changes not saved")
                    .font(.caption).foregroundStyle(model.saveError == nil ? Color.secondary : .red)
                Spacer()
                Button(model.state == .recording ? "Stop" : "Dictate", systemImage: "mic") {
                    if model.state == .recording { model.stopRecording() }
                    else { model.startRecording(noteID: note.id, handsFree: true) }
                }.disabled(model.state != .recording && (!model.canRecord || model.state.busy))
                Menu {
                    Button("Copy note") { InsertionService.copy(note.text) }
                    Button("Export as text…") {
                        FilePanels.save(name: "\(note.title.isEmpty ? "Far Flow Note" : note.title).txt", type: .plainText) { url in
                            do { try note.text.write(to: url, atomically: true, encoding: .utf8) }
                            catch { model.error=error.localizedDescription }
                        }
                    }
                    Divider()
                    Button("Delete note…", role: .destructive) { deleting=note }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25).accessibilityLabel("Note actions")
            }
            TextEditor(text: Binding(
                get: { model.data.notes.first { $0.id == note.id }?.text ?? "" },
                set: { model.data.updateNote(id: note.id, text: $0) }
            )).font(.system(size: 15)).scrollContentBackground(.hidden).accessibilityIdentifier("notes.editor")
            Text("Hold \(model.shortcutTitle) or use Dictate to append speech to this note. Each recording can last up to five minutes.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22)
    }
}

struct InsightsView: View {
    @Bindable var model: AppModel
    var totalWords: Int {model.data.history.reduce(0){$0+$1.wordCount}}
    var duration: Double {model.data.history.reduce(0){$0+$1.duration}}
    var latency: Double {model.data.history.isEmpty ? 0 : model.data.history.reduce(0){$0+$1.processingSeconds}/Double(model.data.history.count)}
    var daily: [(date:Date,words:Int)] {
        (0..<7).reversed().map{offset in let day=Calendar.current.startOfDay(for:Date().addingTimeInterval(-Double(offset)*86400));return(day,model.data.history.filter{Calendar.current.isDate($0.createdAt,inSameDayAs:day)}.reduce(0){$0+$1.wordCount})}
    }
    var body: some View {
        ScrollView {VStack(alignment:.leading,spacing:28){
            PageHeading(title:"Insights",subtitle:"Your local dictation history, measured."){EmptyView()}
            HStack(spacing:0){metric("Words",value:totalWords.formatted());Divider().frame(height:50);metric("Dictations",value:model.data.history.count.formatted());Divider().frame(height:50);metric("Speaking time",value:"\(Int(duration/60)) min");Divider().frame(height:50);metric("Avg. processing",value:String(format:"%.1fs",latency))}
            Divider()
            SectionLabel(title:"Words over the last seven days")
            Chart(daily,id:\.date){item in BarMark(x:.value("Day",item.date,unit:.day),y:.value("Words",item.words)).foregroundStyle(FlowTheme.green).cornerRadius(4)}.chartXAxis{AxisMarks(values:.stride(by:.day)){AxisValueLabel(format:.dateTime.weekday(.abbreviated))}}.frame(height:210)
            Divider()
            SectionLabel(title:"Languages")
            ForEach([("en","English"),("nl","Dutch")],id:\.0){code,name in HStack{Text(name);Spacer();Text("\(model.data.history.filter{$0.language==code}.count) dictations").foregroundStyle(.secondary)}.font(.subheadline)}
            Text("Statistics reflect retained history only. Deleting a dictation or changing retention updates these totals. Audio-file imports do not contribute speaking time.").font(.caption).foregroundStyle(.secondary)
        }.padding(34)}
    }
    private func metric(_ label:String,value:String)->some View{VStack(alignment:.leading,spacing:10){Text(label).font(.caption).foregroundStyle(.secondary);Text(value).font(.system(size:27,weight:.medium,design:.rounded))}.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12)}
}
