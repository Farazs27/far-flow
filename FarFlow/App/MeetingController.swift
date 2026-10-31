import Foundation
import Observation
import FarFlowCore

/// Owns meeting work independently of the window. Reuses the app's two local
/// engines and persists through AppModel's existing SQLite document.
@Observable @MainActor final class MeetingController {
    enum Phase { case idle, starting, recording, processing }
    private(set) var phase: Phase = .idle
    private(set) var activeID: UUID?
    private(set) var captureAppBundleID: String?
    private(set) var summaryID: UUID?
    private(set) var summaryProgress = ""
    private(set) var microphoneLevel: Float = 0
    private(set) var systemLevel: Float = 0
    var error: String?
    var selectedID: UUID?
    var busy: Bool { activeID != nil || summaryID != nil }
    var recording: Bool { phase == .starting || phase == .recording }
    var status: String {
        switch phase {
        case .idle: return summaryID == nil ? "Ready" : summaryProgress
        case .starting: return "Preparing meeting audio…"
        case .recording: return "Meeting recording"
        case .processing: return "Finishing meeting transcript…"
        }
    }
    @ObservationIgnored var lookup: (UUID) -> Meeting? = { _ in nil }
    @ObservationIgnored var persist: (Meeting) -> Bool = { _ in false }
    @ObservationIgnored var onFinished: (UUID) -> Void = { _ in }
    private let audioRoot: URL
    private var summaryRun: UUID?
    private let speech: LocalSpeechEngine
    private let writing: LocalCleanupEngine
    private var capture: MeetingCapture?
    private var startTask: Task<Void,Never>?
    private var processingTask: Task<Void,Never>?
    private var summaryTask: Task<Void,Never>?
    private var meterTimer: Timer?
    init(speech: LocalSpeechEngine, writing: LocalCleanupEngine, audioRoot: URL = FlowPaths.root) { self.speech=speech; self.writing=writing; self.audioRoot=audioRoot }

    func start(title: String, appBundleID: String, sourceName: String, deviceID: UInt32, language: DictationLanguage) {
        guard !busy else { return }
        var meeting=Meeting(title:title.trimmingCharacters(in:.whitespacesAndNewlines),sourceName:sourceName,language:language)
        if meeting.title.isEmpty { meeting.title="Meeting · \(Date().formatted(date:.abbreviated,time:.shortened))" }
        guard persist(meeting) else { error="Recording did not start because the meeting could not be saved."; return }
        let id=meeting.id; activeID=id; captureAppBundleID=appBundleID; selectedID=id; phase = .starting; error=nil
        let next=MeetingCapture(spool:MeetingAudioSpool(meetingID:id,root:audioRoot)) { [weak self] message in
            guard let self, self.activeID == id else { return }
            self.error=message; self.stop(reason:message)
        }
        capture=next
        startTask=Task { [weak self] in
            guard let self else { return }
            do {
                try await next.start(appBundleID:appBundleID,deviceID:deviceID)
                guard activeID == id, phase == .starting else { next.stop(); return }
                if var current=lookup(id) { current.startedAt = .now; _ = persist(current) }
                phase = .recording
                meterTimer=Timer.scheduledTimer(withTimeInterval:0.3,repeats:true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let levels=self.capture?.levels else { return }
                        self.microphoneLevel=levels.microphone; self.systemLevel=levels.system
                    }
                }
                process(id)
            } catch {
                guard activeID == id else { return }
                self.error="Meeting capture could not start. Check Microphone and Screen & System Audio Recording permissions. \(error.localizedDescription)"
                stop(reason:self.error)
            }
            startTask=nil
        }
    }
    func stop(reason: String? = nil) {
        guard let id=activeID, phase != .idle else { return }
        let wasStarting=phase == .starting
        phase = .processing; meterTimer?.invalidate(); meterTimer=nil
        let captureIssue=capture?.stop(); capture=nil; microphoneLevel=0; systemLevel=0
        let finalIssue=reason ?? captureIssue
        if wasStarting { startTask?.cancel() }
        if var value=lookup(id) {
            value.endedAt=value.endedAt ?? .now
            value.status=finalIssue == nil ? .processing : .interrupted
            value.issue=finalIssue
            _ = persist(value)
        }
        if processingTask == nil { process(id) }
    }
    func recover(_ id: UUID) {
        guard !busy, var value=lookup(id) else { return }
        activeID=id; selectedID=id; phase = .processing; error=nil
        value.status = .processing; value.issue=nil
        guard persist(value) else { activeID=nil; phase = .idle; error="Could not save the meeting. Retry after fixing local storage."; return }
        process(id)
    }
    func pauseProcessing() {
        guard phase == .processing else { return }
        shutdown(reason:"Transcription paused. Finish saved audio when ready.")
    }
    func shutdown(reason: String = "Recording was interrupted. Completed transcript and pending audio remain on this Mac.") {
        startTask?.cancel(); processingTask?.cancel(); summaryTask?.cancel()
        startTask=nil; processingTask=nil; summaryTask=nil; summaryID=nil; summaryRun=nil
        capture?.stop(); capture=nil; meterTimer?.invalidate(); meterTimer=nil
        if let id=activeID, var value=lookup(id) {
            value.status = .interrupted; value.endedAt=value.endedAt ?? .now; value.issue=reason
            _ = persist(value)
        }
        activeID=nil; captureAppBundleID=nil; phase = .idle; microphoneLevel=0; systemLevel=0
    }
    private func process(_ id: UUID) {
        processingTask=Task { [weak self] in
            guard let self else { return }
            let spool=MeetingAudioSpool(meetingID:id,root:audioRoot)
            do {
                while activeID == id {
                    try Task.checkCancellation()
                    if let chunk=try spool.pending().first {
                        guard let snapshot=lookup(id) else { throw FlowError.message("The meeting is no longer available.") }
                        let text: String
                        let duration: Double
                        if let existing=snapshot.segments.first(where: { $0.id == chunk.id }) {
                            text=existing.text; duration=existing.duration
                        } else {
                            let samples=try spool.samples(chunk)
                            duration=Double(samples.count)/16000
                            text=try await speech.transcribe(samples:samples,language:snapshot.language)
                        }
                        try Task.checkCancellation()
                        guard activeID == id, var current=lookup(id) else { return }
                        current.checkpoint(MeetingSegment(id:chunk.id,source:chunk.source,offset:chunk.offset,duration:duration,text:text))
                        guard persist(current) else { throw FlowError.message("Transcript could not be saved. Audio remains on this Mac for retry.") }
                        try spool.remove(chunk)
                    } else if phase == .processing {
                        if var current=lookup(id) {
                            if current.issue == nil { current.status = .complete }
                            guard persist(current) else { throw FlowError.message("Could not save the completed meeting.") }
                        }
                        activeID=nil; captureAppBundleID=nil; phase = .idle; processingTask=nil
                        if lookup(id)?.status == .complete { onFinished(id) }
                        return
                    } else {
                        try await Task.sleep(for:.milliseconds(500))
                    }
                }
            } catch is CancellationError { return }
            catch {
                guard activeID == id else { return }
                self.error=error.localizedDescription
                shutdown(reason:error.localizedDescription)
            }
        }
    }
    func summarize(_ id: UUID) {
        guard !busy, let value=lookup(id), !value.transcript.isEmpty else { return }
        do {
            guard try MeetingAudioSpool(meetingID:id,root:audioRoot).pending().isEmpty else {
                error="Finish saved audio before summarizing so the entire transcript is included."; return
            }
        } catch { self.error=error.localizedDescription; return }
        let run=UUID(); summaryRun=run
        summaryID=id; error=nil; summaryProgress="Preparing local summary…"
        summaryTask=Task { [weak self] in
            guard let self else { return }
            do {
                let result=try await writing.summarizeMeeting(value.transcript,language:value.summaryLanguage) { [weak self] message in
                    await self?.setSummaryProgress(message,for:run)
                }
                try Task.checkCancellation()
                guard summaryRun == run, var current=lookup(id) else { return }
                guard !result.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw FlowError.message("The local model returned an empty summary. Your previous summary is unchanged.") }
                current.summary=result; current.summaryDate = .now
                if !persist(current) { self.error="Summary is visible but could not be saved. Export it before quitting." }
            } catch is CancellationError { }
            catch { self.error=error.localizedDescription }
            if summaryRun == run { summaryRun=nil; summaryID=nil; summaryTask=nil; summaryProgress="" }
        }
    }
    private func setSummaryProgress(_ message: String, for run: UUID) { if summaryRun == run { summaryProgress=message } }
    func cancelSummary() { summaryTask?.cancel(); summaryTask=nil; summaryID=nil; summaryRun=nil; summaryProgress="" }
}
