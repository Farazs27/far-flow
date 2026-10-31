import AppKit
import SwiftUI

/// Nonactivating, app-owned prompt: works with the hub closed, without stealing
/// focus or requiring notification permission. No audio starts from detection.
@MainActor final class MeetingPromptPanel {
    private let panel: NSPanel
    init(model: AppModel) {
        panel=NSPanel(contentRect:NSRect(x:0,y:0,width:390,height:174),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isFloatingPanel=true; panel.level = .floating; panel.hidesOnDeactivate=false
        panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=true; panel.isReleasedWhenClosed=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.title="Far Flow meeting prompt"
        panel.contentView=NSHostingView(rootView:MeetingPromptView(model:model))
    }
    func show() {
        guard let screen=NSScreen.main else { return }
        panel.setFrameOrigin(NSPoint(x:screen.visibleFrame.maxX-410,y:screen.visibleFrame.minY+24))
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
    func close() { panel.close() }
}

private struct MeetingPromptView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if let candidate=model.meetingSuggestion {
                Label("Record this meeting?",systemImage:"person.2.wave.2").font(.headline)
                Text("\(candidate.name) is using your microphone. Record your microphone and this app’s audio locally?").font(.subheadline)
                Text("Let participants know before recording.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Not now") { model.dismissMeetingPrompt() }
                    Spacer()
                    Button("Record meeting") { model.acceptMeetingSuggestion() }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("meetingPrompt.record")
                }
            } else if model.meetingEndSuggested {
                Label("Meeting finished?",systemImage:"stop.circle").font(.headline)
                Text("The meeting app stopped using its microphone. Far Flow is still recording; you may just be muted.").font(.subheadline)
                HStack {
                    Button("Keep recording") { model.dismissMeetingPrompt() }
                    Spacer()
                    Button("Stop & transcribe") { model.dismissMeetingPrompt(); model.meeting.stop() }.buttonStyle(.borderedProminent)
                }
            } else if model.finishedMeetingID != nil {
                Label("Your transcript is ready",systemImage:"checkmark.circle").font(.headline)
                Text("Saved on this Mac. Open the meeting to read the transcript, add notes and review its summary.").font(.subheadline)
                HStack {
                    Button("Dismiss") { model.dismissMeetingPrompt() }
                    Spacer()
                    Button("Open meeting") { model.openFinishedMeeting() }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(20).frame(width:390,height:174,alignment:.leading)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:16))
    }
}
