import SwiftUI
import FarFlowCore

struct MeetingsView: View {
    @Bindable var model: AppModel
    @State private var title = ""
    @State private var sourceID = "choose"
    @State private var apps: [MeetingAppChoice] = []
    @State private var search = ""
    @State private var tab = "transcript"
    @State private var deleting: Meeting?
    @State private var pending = 0
    @State private var replacingSummary = false
    private var selected: Meeting? {
        model.data.meetings?.first { $0.id == model.meeting.selectedID } ?? model.data.meetings?.first
    }
    private var canWork: Bool { !model.loadingModels && !model.meeting.busy && model.modelOperation == nil && !model.transforming && !model.state.busy && model.saveError == nil }
    private var available: Bool { canWork && model.speechReady && !model.loadingModels }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            PageHeading(title:"Meetings",subtitle:"Record both sides. Keep the transcript and summary on your Mac.") { EmptyView() }
            if let message=model.meeting.error {
                HStack(alignment:.top) {
                    Label(message,systemImage:"exclamationmark.triangle").font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Dismiss") { model.meeting.error=nil }
                }.padding(10).background(Color.orange.opacity(0.1),in:RoundedRectangle(cornerRadius:8))
            }
            if model.meeting.activeID != nil {
                HStack {
                    Circle().fill(model.meeting.recording ? Color.red : FlowTheme.green).frame(width:8,height:8)
                    Text(model.meeting.status).font(.subheadline.weight(.medium))
                    Spacer()
                    if model.meeting.recording {
                        audioMeter("Microphone",value:model.meeting.microphoneLevel)
                        audioMeter("Meeting app",value:model.meeting.systemLevel)
                        Button("Stop recording",systemImage:"stop.fill") { model.meeting.stop() }.buttonStyle(FlowActionStyle()).accessibilityIdentifier("meetings.stop")
                    } else { Button("Pause transcription") { model.meeting.pauseProcessing() } }
                }
                Text("Closing this window keeps recording. Use Stop recording when finished. Use headphones to avoid recording the call twice through your microphone.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Meeting language",selection:Binding(get:{model.data.preferences.meetingLanguage ?? .auto},set:{model.data.preferences.meetingLanguage=$0})) {
                    Text("Auto · English / Dutch").tag(DictationLanguage.auto)
                    Text("English").tag(DictationLanguage.english)
                    Text("Nederlands").tag(DictationLanguage.dutch)
                }.frame(width:310).disabled(!canWork)
                HStack {
                    TextField("Meeting title (optional)",text:$title).textFieldStyle(.roundedBorder).accessibilityIdentifier("meetings.newTitle")
                    Picker("Audio from",selection:$sourceID) {
                        Text("Choose meeting app").tag("choose")
                        Text("All Mac audio").tag("")
                        ForEach(apps) { Text($0.name).tag($0.id) }
                    }.frame(width:225)
                    Button { apps=MeetingAppChoice.running } label: { Image(systemName:"arrow.clockwise") }.help("Refresh running apps")
                    Button("Start recording",systemImage:"record.circle") {
                        let name=sourceID.isEmpty ? "All Mac audio" : apps.first { $0.id == sourceID }?.name ?? sourceID
                        model.startMeeting(title:title,appBundleID:sourceID,sourceName:name)
                    }.buttonStyle(FlowActionStyle()).disabled(!available || sourceID == "choose").accessibilityIdentifier("meetings.start")
                }
                Text("Records your microphone and the selected app's audio. Audio chunks stay on this Mac until transcribed, then are deleted. No video is saved. Let participants know before recording.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("macOS may ask for Screen & System Audio Recording permission. Browser selection captures all audio from that browser.")
                    Button("Open permissions") { model.openPrivacy("Privacy_ScreenCapture") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing:0) {
                VStack(spacing:10) {
                    TextField("Search meetings",text:$search).textFieldStyle(.roundedBorder).padding(10)
                    ScrollView {
                        LazyVStack(spacing:4) {
                            ForEach((model.data.meetings ?? []).filter { search.isEmpty || $0.title.localizedStandardContains(search) || $0.notes.localizedStandardContains(search) || $0.summary.localizedStandardContains(search) || $0.segments.contains { $0.text.localizedStandardContains(search) } }) { value in
                                Button { model.meeting.selectedID=value.id } label: {
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(value.title.isEmpty ? "Untitled meeting" : value.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                        Text(value.startedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                                        Text(value.status.rawValue.capitalized).font(.caption).foregroundStyle(value.status == .recording ? Color.red : .secondary)
                                    }.frame(maxWidth:.infinity,alignment:.leading).padding(12)
                                        .background(selected?.id == value.id ? FlowTheme.green.opacity(0.09) : .clear,in:RoundedRectangle(cornerRadius:8))
                                }.buttonStyle(.plain)
                            }
                        }.padding(6)
                    }
                }.frame(width:210)
                Divider()
                if let value=selected { detail(value).id(value.id) }
                else { EmptyFlow(symbol:"person.2.wave.2",title:"Keep the conversation",detail:"Choose your meeting app and start recording. Transcripts, notes and summaries stay local.") }
            }.overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.primary.opacity(0.08)))
        }.padding(30)
        .onAppear { apps=MeetingAppChoice.running }
        .task(id:selected?.id) {
            while !Task.isCancelled {
                if let value=selected {
                    do { pending=try MeetingAudioSpool(meetingID:value.id).pending().count }
                    catch { model.meeting.error=error.localizedDescription }
                }
                do { try await Task.sleep(for:.seconds(1)) } catch { return }
            }
        }
        .confirmationDialog("Delete this meeting and its pending audio?",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {
            Button("Delete meeting",role:.destructive) { if let value=deleting { model.deleteMeeting(value.id) }; deleting=nil }
        } message: { Text("Export any transcript or notes you want to keep first.") }
        .confirmationDialog("Replace the current summary?",isPresented:$replacingSummary,titleVisibility:.visible) {
            Button("Generate new summary") { if let value=selected { model.meeting.summarize(value.id) } }
        } message: { Text("Your edited summary will be replaced only after a new local summary finishes successfully.") }
    }
    private func detail(_ value: Meeting) -> some View {
        VStack(alignment:.leading,spacing:14) {
            TextField("Untitled meeting",text:Binding(get:{selected?.title ?? ""},set:{model.updateMeeting(value.id,title:$0)}))
                .font(.title2.weight(.medium)).textFieldStyle(.plain).accessibilityIdentifier("meetings.title")
            HStack {
                Text(value.sourceName).font(.caption).foregroundStyle(.secondary)
                if let end=value.endedAt { Text(Meeting.timestamp(end.timeIntervalSince(value.startedAt))).font(.caption).monospacedDigit() }
                Spacer()
                Menu {
                    Button("Copy transcript") { InsertionService.copy(value.transcript) }
                    Button("Export meeting…") {
                        FilePanels.save(name:"\(value.title.isEmpty ? "Meeting" : value.title).txt",type:.plainText) { url in
                            do { try value.exportText.write(to:url,atomically:true,encoding:.utf8) }
                            catch { model.meeting.error=error.localizedDescription }
                        }
                    }
                    Divider()
                    Button("Delete meeting…",role:.destructive) { deleting=value }.disabled(model.meeting.activeID == value.id || model.meeting.summaryID == value.id)
                } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:26).accessibilityLabel("Meeting actions")
            }
            if let issue=value.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
            if pending>0 && model.meeting.activeID != value.id {
                HStack {
                    Text("\(pending) saved audio chunks to finish").font(.caption)
                    Spacer()
                    Button("Finish saved audio") { model.meeting.recover(value.id) }.disabled(!available)
                }
            }
            Picker("Meeting content",selection:$tab) { Text("Transcript").tag("transcript"); Text("Notes").tag("notes"); Text("Summary").tag("summary") }.pickerStyle(.segmented)
            if tab == "notes" {
                TextEditor(text:Binding(get:{selected?.notes ?? ""},set:{model.updateMeeting(value.id,notes:$0)}))
                    .font(.system(size:14)).scrollContentBackground(.hidden).accessibilityIdentifier("meetings.notes")
            } else if tab == "summary" {
                HStack {
                    if model.meeting.summaryID == value.id {
                        ProgressView().controlSize(.small)
                        Text(model.meeting.summaryProgress).font(.caption)
                        Spacer(); Button("Cancel") { model.meeting.cancelSummary() }
                    } else {
                        Text("AI draft · verify against the transcript").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(value.summary.isEmpty ? "Generate summary" : "Regenerate") {
                            if value.summary.isEmpty { model.meeting.summarize(value.id) } else { replacingSummary=true }
                        }.disabled(!canWork || pending>0 || value.transcript.isEmpty || !model.installedModels.contains("qwen-cleanup"))
                    }
                }
                if !model.installedModels.contains("qwen-cleanup") { Button("Install the local writing model") { model.page = .models } }
                TextEditor(text:Binding(get:{selected?.summary ?? ""},set:{model.updateMeeting(value.id,summary:$0)}))
                    .font(.system(size:14)).scrollContentBackground(.hidden).disabled(model.meeting.summaryID == value.id).accessibilityIdentifier("meetings.summary")
            } else {
                ScrollView {
                    if value.transcript.isEmpty {
                        Text(model.meeting.recording ? "Speech appears after each audio chunk is processed, about every 30 seconds." : "No speech transcribed yet.")
                            .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                    } else {
                        Text(value.transcript).font(.system(size:14)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.frame(maxHeight:.infinity)
                Text("Microphone and Meeting app identify audio sources, not individual speakers. Overlapping speech and speaker echo can affect recognition.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20)
    }
    private func audioMeter(_ title: String, value: Float) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.caption2)
            ProgressView(value:Double(value)).frame(width:80).tint(FlowTheme.green).accessibilityLabel("\(title) input level")
        }
    }
}
