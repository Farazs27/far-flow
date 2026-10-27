import SwiftUI
import FarFlowCore

struct DictionaryView: View {
    @Bindable var model: AppModel
    @State private var editing: DictionaryEntry?
    @State private var search=""
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:0) {
            PageHeading(title:"Dictionary",subtitle:"Names and words, spelled your way.") { Button("Add word",systemImage:"plus") { editing=DictionaryEntry(word:"") }.buttonStyle(FlowActionStyle()).accessibilityIdentifier("dictionary.add") }
            HStack {
                TextField("Search words",text:$search).textFieldStyle(.roundedBorder).frame(width:250);Spacer()
                Button("Import") { FilePanels.openJSON { url in do { let entries=try JSONDecoder().decode([DictionaryEntry].self,from:Data(contentsOf:url)); for entry in entries where !entry.word.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !model.data.dictionary.contains(where:{$0.word.localizedCaseInsensitiveCompare(entry.word) == .orderedSame}) { model.data.dictionary.append(entry) } } catch { model.error="Choose a Far Flow dictionary export. \(error.localizedDescription)" } } }
                Button("Export") { FilePanels.save(name:"Far Flow Dictionary.json") { url in do { try JSONEncoder().encode(model.data.dictionary).write(to:url,options:.atomic) } catch { model.error=error.localizedDescription } } }
            }.padding(.bottom,25)
            if model.data.dictionary.isEmpty { EmptyFlow(symbol:"book.closed",title:"Make it personal",detail:"Add names, businesses, and English or Dutch terms you use often. An optional spoken alias fixes recurring recognition mistakes.") }
            ForEach(model.data.dictionary.filter { search.isEmpty || $0.word.localizedCaseInsensitiveContains(search) || $0.alias.localizedCaseInsensitiveContains(search) }) { entry in
                HStack {
                    VStack(alignment:.leading,spacing:6) { Text(entry.word).font(.headline);Text(entry.alias.isEmpty ? "Exact spelling" : "When you say “\(entry.alias)”").font(.caption).foregroundStyle(.secondary) }
                    Spacer();Text(entry.language == .auto ? "Both languages":entry.language.title).font(.caption).foregroundStyle(.secondary)
                    Button("Edit") { editing=entry }
                }.padding(.vertical,19);Divider()
            }
        }.padding(34) }
        .sheet(item:$editing) { entry in DictionaryEditor(model:model,entry:entry) }
    }
}

struct DictionaryEditor: View {
    @Bindable var model: AppModel
    @State var entry: DictionaryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var validation=""
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Dictionary word").font(.title2.weight(.semibold))
            Form { TextField("Correct spelling",text:$entry.word).accessibilityIdentifier("dictionary.word");TextField("Spoken alias (optional)",text:$entry.alias);Picker("Language",selection:$entry.language) { Text("English + Dutch").tag(DictationLanguage.auto);Text("English").tag(DictationLanguage.english);Text("Dutch").tag(DictationLanguage.dutch) } }
            Text("Matches whole words and phrases. Original dictation remains available in history.").font(.caption).foregroundStyle(.secondary)
            if !validation.isEmpty { Text(validation).font(.caption).foregroundStyle(.red) }
            HStack {
                if model.data.dictionary.contains(where:{$0.id==entry.id}) { Button("Delete",role:.destructive) { model.data.dictionary.removeAll{$0.id==entry.id};dismiss() } }
                Spacer();Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save word") { save() }.buttonStyle(FlowActionStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width:500)
    }
    private func save() {
        entry.word=entry.word.trimmingCharacters(in:.whitespacesAndNewlines);entry.alias=entry.alias.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !entry.word.isEmpty else { validation="Enter the spelling you want to use.";return }
        guard !model.data.dictionary.contains(where:{$0.id != entry.id && ($0.word.localizedCaseInsensitiveCompare(entry.word) == .orderedSame || (!$0.alias.isEmpty && $0.alias.localizedCaseInsensitiveCompare(entry.alias) == .orderedSame))}) else { validation="This word or alias is already in your dictionary.";return }
        if let i=model.data.dictionary.firstIndex(where:{$0.id==entry.id}) { model.data.dictionary[i]=entry } else { model.data.dictionary.append(entry) };dismiss()
    }
}

struct SnippetsView: View {
    @Bindable var model: AppModel
    @State private var editing: VoiceSnippet?
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:0) {
            PageHeading(title:"Snippets",subtitle:"Say a short phrase. Insert the exact text.") { Button("Add snippet",systemImage:"plus") { editing=VoiceSnippet(trigger:"",expansion:"") }.buttonStyle(FlowActionStyle()) }
            if model.data.snippets.isEmpty { EmptyFlow(symbol:"text.bubble",title:"A shortcut for your voice",detail:"Save your signature, an introduction, or a recurring reply. Say the trigger on its own to insert it unchanged.") }
            ForEach(model.data.snippets) { snippet in
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:10) { Text("“\(snippet.trigger)”").font(.headline).foregroundStyle(FlowTheme.green);Text(snippet.expansion).font(.subheadline).foregroundStyle(.secondary).lineLimit(4) }
                    Spacer();Button("Copy") { InsertionService.copy(snippet.expansion) };Button("Edit") { editing=snippet }
                }.padding(.vertical,22);Divider()
            }
            Text("Triggers match the entire dictation. Mentioning a trigger inside a longer sentence will not expand it.").font(.caption).foregroundStyle(.secondary).padding(.top,28)
        }.padding(34) }.sheet(item:$editing) { SnippetEditor(model:model,snippet:$0) }
    }
}

struct SnippetEditor: View {
    @Bindable var model: AppModel
    @State var snippet: VoiceSnippet
    @Environment(\.dismiss) private var dismiss
    @State private var validation=""
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Voice snippet").font(.title2.weight(.semibold))
            TextField("Spoken trigger, such as “my signature”",text:$snippet.trigger).textFieldStyle(.roundedBorder)
            Text("Text to insert").font(.subheadline.weight(.medium))
            TextEditor(text:$snippet.expansion).font(.body).frame(height:155).padding(8).background(.background,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(.quaternary))
            if !validation.isEmpty { Text(validation).font(.caption).foregroundStyle(.red) }
            HStack {
                if model.data.snippets.contains(where:{$0.id==snippet.id}) { Button("Delete",role:.destructive) {model.data.snippets.removeAll{$0.id==snippet.id};dismiss()} }
                Spacer();Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Button("Save snippet") {
                    snippet.trigger=snippet.trigger.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !snippet.trigger.isEmpty,!snippet.expansion.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {validation="Enter a trigger and the text to insert.";return}
                    guard !model.data.snippets.contains(where:{$0.id != snippet.id && TextPipeline.normalizedTrigger($0.trigger)==TextPipeline.normalizedTrigger(snippet.trigger)}) else {validation="A snippet already uses this trigger.";return}
                    if let i=model.data.snippets.firstIndex(where:{$0.id==snippet.id}) {model.data.snippets[i]=snippet}else{model.data.snippets.append(snippet)};dismiss()
                }.buttonStyle(FlowActionStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width:530)
    }
}

struct StylesView: View {
    @Bindable var model: AppModel
    var apps: [NSRunningApplication] { NSWorkspace.shared.runningApplications.filter{$0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier}.sorted{($0.localizedName ?? "")<($1.localizedName ?? "")} }
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:22) {
            PageHeading(title:"Styles",subtitle:"Keep your words. Choose how much to tidy them.") { EmptyView() }
            SectionLabel(title:"Automatic cleanup")
            ForEach(CleanupLevel.allCases) { level in
                Button {model.data.preferences.cleanup=level} label:{ HStack(spacing:15) { Image(systemName:model.data.preferences.cleanup==level ? "largecircle.fill.circle":"circle").foregroundStyle(FlowTheme.green);VStack(alignment:.leading,spacing:5){Text(level.title).font(.headline);Text(level.detail).font(.subheadline).foregroundStyle(.secondary)};Spacer()} }.buttonStyle(.plain)
            }
            Divider().padding(.vertical,8)
            HStack { VStack(alignment:.leading,spacing:6){Text("Default writing style").font(.headline);Text("Applied when local AI cleanup is enabled.").font(.caption).foregroundStyle(.secondary)};Spacer();Picker("Default style",selection:$model.data.preferences.style){ForEach(WritingStyle.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:170) }
            Divider().padding(.vertical,8)
            HStack {SectionLabel(title:"App styles");Spacer();Menu("Add app",systemImage:"plus"){ForEach(apps,id:\.processIdentifier){app in Button(app.localizedName ?? "App"){guard let bundle=app.bundleIdentifier,!model.data.appStyles.contains(where:{$0.bundleID==bundle})else{return};model.data.appStyles.append(AppStyle(appName:app.localizedName ?? "App",bundleID:bundle,style:.standard))}}}}
            if model.data.appStyles.isEmpty {Text("Open an app, then add a style for it. Your choice applies to both English and Dutch dictation.").font(.subheadline).foregroundStyle(.secondary)}
            ForEach($model.data.appStyles){$rule in HStack{Text(rule.appName);Spacer();Picker("Style for \(rule.appName)",selection:$rule.style){ForEach(WritingStyle.allCases){Text($0.title).tag($0)}}.labelsHidden().frame(width:170);Button{model.data.appStyles.removeAll{$0.id==rule.id}}label:{Image(systemName:"minus.circle")}.buttonStyle(.plain).help("Remove app style")}}
            Divider().padding(.vertical,8)
            Text("Raw recognition is always available while reviewing a dictation. Use None for literal wording and code. Dutch and English are kept in their original language.").font(.caption).foregroundStyle(.secondary)
        }.padding(34) }
    }
}
