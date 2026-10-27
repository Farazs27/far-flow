import AppKit
import AVFoundation
import ServiceManagement
import Observation
import FarFlowCore

enum FlowPage: String, CaseIterable, Identifiable {
    case dictation="Dictation", dictionary="Dictionary", snippets="Snippets", styles="Styles", transforms="Transforms", scratchpad="Scratchpad", insights="Insights", models="Models", settings="Settings"
    var id: String { rawValue }
    var symbol: String { switch self { case .dictation: "mic"; case .dictionary: "book.closed"; case .snippets: "text.bubble"; case .styles: "sparkle"; case .transforms: "arrow.triangle.2.circlepath"; case .scratchpad: "square.and.pencil"; case .insights: "chart.bar.xaxis"; case .models: "shippingbox"; case .settings: "gearshape" } }
}

enum RecordingState: Equatable {
    case idle, recording, transcribing, cleaning, inserting
    var title: String { switch self { case .idle: "Ready"; case .recording: "Listening"; case .transcribing: "Transcribing on this Mac"; case .cleaning: "Cleaning up on this Mac"; case .inserting: "Inserting" } }
    var busy: Bool { self != .idle }
}

@Observable @MainActor final class AppModel {
    var data: UserData { didSet { save() } }
    var page: FlowPage = .dictation
    var state: RecordingState = .idle
    var meter: Float = 0
    var recordingDuration: Double = 0
    var handsFree=false
    var lastRaw=""
    var lastText=""
    var lastStatus="Your voice stays on this Mac."
    var error: String?
    var speechReady=false
    var writingReady=false
    var loadingModels=false
    var modelStatus="Checking local models…"
    var modelProgress: [String:Double] = [:]
    var modelOperation: String?
    var installedModels: Set<String> = []
    var manifests: [ModelManifest] = []
    var devices: [InputDevice] = []
    var accessibilityGranted=false
    var microphoneGranted=false
    var hotkeyReady=false
    var mediaStatus="Checking local playback…"
    var transformInput=""
    var transformOutput=""
    var transformKind: TransformKind = .polish
    var transforming=false
    var showOnboarding=false
    var showTranscript=false
    var transformTarget: InsertionTarget?
    var transformUndoTarget: InsertionTarget?
    var transformUndoText=""
    var lastExternalTarget: InsertionTarget?
    var shortcutTitle: String { data.preferences.shortcut == "fn" ? "fn" : "⌃ ⌥ Space" }
    var isDemo: Bool { Bundle.main.object(forInfoDictionaryKey:"FarFlowDemoDataDirectory") is String }
    var canRecord: Bool { speechReady && modelOperation==nil }
    let speech=LocalSpeechEngine()
    let writing=LocalCleanupEngine()
    let installer=ModelInstaller()
    let shortcuts=ShortcutService()
    private var store: LocalStore?
    private var storeWritable=true
    private let audio=AudioCapture()
    private let playback=MediaPlaybackService()
    private var activeSession: UUID?
    private var sessionTask: Task<Void,Never>?
    private var warmupTask: Task<Void,Never>?
    private var transformTask: Task<Void,Never>?
    private var terminating=false
    private var meterTimer: Timer?
    private var housekeepingTimer: Timer?
    private var sessionWantsReview=false
    private var targetNote: UUID?
    private var overlay: RecordingPanel?
    private var observers: [NSObjectProtocol]=[]
    private var uiTesting=false
    private var lastRetentionCheck=Date.distantPast

    init() {
        FlowTheme.registerFonts()
        uiTesting=ProcessInfo.processInfo.arguments.contains("--ui-testing") || Bundle.main.object(forInfoDictionaryKey:"FarFlowDemoDataDirectory") is String
        data=UserData()
        do {
            let database=try LocalStore(); store=database; data=try database.load()
        } catch { storeWritable=false; self.error="Local data could not be opened. Your existing database has been preserved. \(error.localizedDescription)" }
        if let path=Bundle.main.url(forResource:"ModelManifest",withExtension:"json"), let bytes=try? Data(contentsOf:path) { manifests=(try? JSONDecoder().decode([ModelManifest].self,from:bytes)) ?? [] }
        if (data.preferences.interfaceRevision ?? 0)<2 {
            data.preferences.interfaceRevision=2;data.preferences.appearance="light";data.preferences.alwaysShowBar=true;data.preferences.showWelcome=true
            save()
        }
        refreshModels(); refreshPermissions(); devices=AudioCapture.devices()
        showOnboarding = !data.preferences.onboardingComplete && !uiTesting
    }
    func launch() {
        // Supply the current artwork directly as well as through Launch Services.
        if let url=Bundle.main.url(forResource:"FarFlowAppIcon",withExtension:"icns"),let icon=NSImage(contentsOf:url) {NSApp.applicationIconImage=icon}
        overlay=RecordingPanel(model:self)
        playback.onChange = {[weak self] in guard let self else{return};self.mediaStatus=self.playback.status}
        if !uiTesting{playback.start()}
        shortcuts.onStart = { [weak self] in self?.startRecording() }
        shortcuts.onStop = { [weak self] in self?.stopRecording() }
        shortcuts.onToggle = { [weak self] in self?.toggleRecording() }
        shortcuts.onLock = { [weak self] in if self?.state == .recording {self?.handsFree=true} }
        shortcuts.onCancel = { [weak self] in self?.cancelRecording() }
        shortcuts.shortcut=data.preferences.shortcut
        if !uiTesting { shortcuts.start() }
        hotkeyReady=shortcuts.available
        let center=NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.cancelRecording() } })
        observers.append(center.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] note in
            guard let app=note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor [weak self] in self?.lastExternalTarget=InsertionService.capture() }
        })
        observers.append(NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:nil,queue:.main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Startup may post a delayed configuration notification while
                // the engine is already healthy. Recover only a stopped graph.
                if self.state == .recording && self.audio.needsRecovery(after:notification.object) { self.stopRecording(); self.lastStatus="Microphone changed. Your captured speech is being recovered." }
                self.devices=AudioCapture.devices()
            }
        })
        housekeepingTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }
            self.refreshPermissions()
            if Date().timeIntervalSince(self.lastRetentionCheck)>60 {
                self.lastRetentionCheck = .now
                if let interval=self.data.preferences.retention.interval,self.data.history.contains(where:{interval==0 || $0.createdAt < Date().addingTimeInterval(-interval)}) {self.data.enforceRetention()}
            }
            if !self.shortcuts.available && self.accessibilityGranted && !self.uiTesting { self.shortcuts.start(); self.hotkeyReady=self.shortcuts.available }
            if self.state == .recording && !self.microphoneGranted { self.cancelRecording(); self.error="Microphone permission was revoked. Enable it in System Settings." }
        } }
        applyAppearance()
        if !uiTesting || isDemo { warmupTask=Task { await warmModels() } }
        if data.preferences.alwaysShowBar { overlay?.show() }
    }
    func terminate() {
        guard !terminating else{return};terminating=true
        activeSession=nil;sessionTask?.cancel();warmupTask?.cancel();transformTask?.cancel()
        audio.cancel();meterTimer?.invalidate();housekeepingTimer?.invalidate()
        shortcuts.stop();playback.stop();overlay?.close();state = .idle;meter=0;save()
    }
    func unloadForTermination() async {
        terminate()
        async let speechStopped:Void=speech.unload()
        async let writingStopped:Void=writing.unload()
        _ = await (speechStopped,writingStopped)
        speechReady=false;writingReady=false
    }
    func save() {
        guard storeWritable, let store else { return }
        do { try store.save(data) } catch { self.error="Your latest change could not be saved. \(error.localizedDescription)" }
    }
    func refreshModels() { installedModels=Set(manifests.filter { $0.isInstalled() }.map(\.id)) }
    func refreshPermissions() {
        accessibilityGranted=AXIsProcessTrusted()
        microphoneGranted=AVCaptureDevice.authorizationStatus(for:.audio) == .authorized
    }
    func requestMicrophone() {
        guard AVCaptureDevice.authorizationStatus(for:.audio) == .notDetermined else {openPrivacy("Privacy_Microphone");return}
        Task { _ = await AVCaptureDevice.requestAccess(for:.audio); refreshPermissions() }
    }
    func requestAccessibility() {
        let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options); openPrivacy("Privacy_Accessibility")
    }
    func openPrivacy(_ pane: String) { if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) } }
    func warmModels() async {
        guard !loadingModels, installedModels.contains("parakeet-v3") else { modelStatus="Install the speech model to begin"; return }
        loadingModels=true; modelStatus="Loading English + Dutch speech…"
        do {
            try await speech.load(); speechReady=true; modelStatus="Speech model ready"
            if data.preferences.useLocalAI && (data.preferences.cleanup == .medium || data.preferences.style != .standard) && installedModels.contains("qwen-cleanup") {
                modelStatus="Loading local writing model…"; try await writing.load(); writingReady=true
            }
            modelStatus=writingReady ? "Local models ready":"Local speech ready"
        } catch { self.error=error.localizedDescription; modelStatus=speechReady ? "Speech ready · writing model unavailable" : "Model could not load" }
        loadingModels=false
    }
    func toggleRecording() {if state == .recording {stopRecording()}else{startRecording(handsFree:true)}}
    func startRecording(noteID: UUID? = nil,handsFree:Bool = false) {
        guard state == .idle else { return }
        guard canRecord else { page = .models; lastStatus="Wait for the speech model to load."; return }
        guard microphoneGranted else { showOnboarding=true; requestMicrophone(); return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier && !accessibilityGranted {
            lastStatus="Enable Accessibility to dictate into other apps.";showOnboarding=true;openHub();return
        }
        let target=InsertionService.capture()
        guard target?.secure != true else { lastStatus="Dictation is blocked in secure text fields."; return }
        sessionWantsReview=NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        targetNote=noteID
        self.handsFree=handsFree
        activeSession=UUID(); lastStatus=""; lastText=""; lastRaw=""; recordingDuration=0
        if let id=activeSession{playback.pause(session:id,enabled:data.preferences.pauseMediaDuringDictation ?? true)}
        do {
            try audio.start(deviceID:data.preferences.inputDeviceID)
            if handsFree {shortcuts.lockRecording()}
            state = .recording; overlay?.show()
            playDictationCue("Tink")
            meterTimer=Timer.scheduledTimer(withTimeInterval:0.08,repeats:true) { [weak self] _ in Task { @MainActor in
                guard let self else { return }
                self.meter=self.audio.meter; self.recordingDuration=self.audio.duration
                if self.recordingDuration>=299 { self.stopRecording() }
            } }
        } catch {if let id=activeSession{playback.resume(session:id)};activeSession=nil;self.handsFree=false;shortcuts.resetGesture();state = .idle; self.error=error.localizedDescription }
    }
    func stopRecording() {
        guard state == .recording, let id=activeSession else { return }
        meterTimer?.invalidate(); meterTimer=nil; meter=0
        let seconds=audio.duration
        let samples: [Float]
        do { samples=try audio.stop() } catch { cancelRecording(); self.error=error.localizedDescription; return }
        playback.resume(session:id)
        state = .transcribing
        let preferences=data.preferences, words=data.dictionary, snippets=data.snippets
        // The user may move the cursor while speaking. Freeze the destination at release,
        // then refuse a later focus change during processing.
        let target=targetNote == nil ? InsertionService.capture():nil, note=targetNote,wantsReview=sessionWantsReview
        let style=data.appStyles.first { $0.bundleID==target?.bundleID }?.style ?? preferences.style
        sessionTask=Task { [weak self] in
            guard let self else { return }
            let began=Date()
            var recognized=""
            do {
                let raw=try await speech.transcribe(samples:samples,language:preferences.language); recognized=raw
                guard self.activeSession==id else { return }
                guard !raw.isEmpty else { finishSession(id,status:"No speech detected"); return }
                self.lastRaw=raw
                let language=TextPipeline.detectedLanguage(raw,preferred:preferences.language)
                self.state = .cleaning
                let result: CleanupResult
                do { result=try await writing.cleanup(raw,level:preferences.cleanup,language:language,style:style,dictionary:words,snippets:snippets,useAI:preferences.useLocalAI) }
                catch is CancellationError { throw CancellationError() }
                catch { result=CleanupResult(text:TextPipeline.lightRules(TextPipeline.applyDictionary(raw,entries:words,language:language),language:language),method:"Fast cleanup · AI unavailable",reviewSuggested:true) }
                try Task.checkCancellation(); guard self.activeSession==id else { return }
                guard !result.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {finishSession(id,status:"No words to insert");return}
                self.lastText=result.text
                self.state = .inserting
                let outcome: String
                if let note, let i=data.notes.firstIndex(where:{$0.id==note}) {
                    data.notes[i].text += (data.notes[i].text.isEmpty ? "" : "\n") + result.text
                    data.notes[i].updatedAt = .now; outcome="Added to scratchpad"
                } else if let target { outcome=await InsertionService.insert(result.text,into:target) }
                else { outcome="Ready to copy" }
                guard self.activeSession==id else { return }
                if preferences.retention != .off {
                    data.history.insert(HistoryItem(raw:raw,text:result.text,language:language,appName:target?.appName ?? (note == nil ? "Far Flow" : "Scratchpad"),duration:seconds,processingSeconds:Date().timeIntervalSince(began),outcome:outcome,cleanup:result.method),at:0)
                    data.enforceRetention()
                }
                finishSession(id,status:outcome + (result.reviewSuggested ? " · review original" : ""))
                // External dictation never raises the dashboard. History and the menu-bar
                // Copy action remain available even when an app cannot verify insertion.
                if wantsReview && target==nil && note==nil {self.showTranscript=true}
            } catch is CancellationError { if self.activeSession==id { finishSession(id,status:"Canceled") } }
            catch {
                guard self.activeSession==id else { return }
                if !recognized.isEmpty { self.lastRaw=recognized; self.lastText=recognized; self.showTranscript=true }
                self.error=error.localizedDescription; finishSession(id,status:"Dictation could not finish")
            }
        }
    }
    func cancelRecording() {
        guard state != .idle else { return }
        guard state != .inserting else {lastStatus="Insertion already requested. Check the destination.";return}
        if let id=activeSession{playback.resume(session:id)}
        activeSession=nil; sessionTask?.cancel(); sessionTask=nil; audio.cancel(); meterTimer?.invalidate(); meterTimer=nil;handsFree=false;shortcuts.resetGesture()
        state = .idle; meter=0; lastStatus="Canceled"; overlay?.hideUnlessPersistent()
    }
    private func finishSession(_ id: UUID,status: String) {
        guard activeSession==id else { return }
        activeSession=nil; state = .idle; lastStatus=status; meter=0; sessionTask=nil;handsFree=false;shortcuts.resetGesture()
        playDictationCue("Pop")
        overlay?.hideAfterDelay()
    }
    private func playDictationCue(_ name:NSSound.Name) {
        guard data.preferences.sounds,let sound=NSSound(named:name) else{return}
        sound.volume=0.12
        sound.play()
    }
    func importAudio(_ url: URL) {
        guard state == .idle, canRecord else { return }
        let id=UUID(); activeSession=id; state = .transcribing
        sessionTask=Task { [weak self] in
            guard let self else { return }
            do {
                let began=Date(), raw=try await speech.transcribe(file:url,language:data.preferences.language)
                guard activeSession==id else { return }
                guard !raw.isEmpty else { finishSession(id,status:"No speech detected"); return }
                lastRaw=raw; state = .cleaning
                let language=TextPipeline.detectedLanguage(raw,preferred:data.preferences.language)
                let result=try await writing.cleanup(raw,level:data.preferences.cleanup,language:language,style:data.preferences.style,dictionary:data.dictionary,snippets:data.snippets,useAI:data.preferences.useLocalAI)
                guard activeSession==id else { return }
                lastText=result.text; showTranscript=true
                if data.preferences.retention != .off { data.history.insert(HistoryItem(raw:raw,text:result.text,language:language,appName:"Audio file",duration:0,processingSeconds:Date().timeIntervalSince(began),outcome:"Ready to copy",cleanup:result.method),at:0); data.enforceRetention() }
                finishSession(id,status:"Audio transcribed on this Mac")
            } catch { guard activeSession==id else { return }; if !lastRaw.isEmpty { lastText=lastRaw; showTranscript=true }; self.error=error.localizedDescription; finishSession(id,status:"Import could not finish") }
        }
    }
    func captureSelection() {
        let refreshed=InsertionService.capture() ?? lastExternalTarget.flatMap { InsertionService.capture(pid:$0.pid) }
        guard let target=refreshed, !target.secure, let text=target.selectedText, !text.isEmpty else { error="Select text in another app, then use the menu bar’s Transform selection action."; return }
        lastExternalTarget=target; transformUndoTarget=nil
        transformInput=text; transformTarget=target; transformOutput=""; page = .transforms
    }
    func runTransform() {
        guard !transforming else { return }; transforming=true; transformOutput=""
        let input=transformInput, kind=transformKind
        transformTask=Task { do { transformOutput=try await writing.transform(input,kind:kind); writingReady=true } catch { self.error=error.localizedDescription }; transforming=false }
    }
    func applyTransform() {
        guard let target=transformTarget, !transformOutput.isEmpty else { return }
        guard let app=NSRunningApplication(processIdentifier:target.pid) else { error="The original app is no longer running."; return }
        app.activate()
        Task {
            try? await Task.sleep(for:.milliseconds(300))
            guard InsertionService.targetUnchanged(target) else { error="The original selection changed. Copy the result to place it yourself."; return }
            lastStatus=await InsertionService.insert(transformOutput,into:target)
            if lastStatus=="Inserted" { transformUndoTarget=target;transformUndoText=transformOutput;transformTarget=nil }
        }
    }
    func undoTransform() {
        guard let target=transformUndoTarget,let app=NSRunningApplication(processIdentifier:target.pid) else { return }
        app.activate()
        Task {try? await Task.sleep(for:.milliseconds(300));lastStatus=await InsertionService.undoTransform(target:target,inserted:transformUndoText);if lastStatus=="Inserted"{transformUndoTarget=nil}}
    }
    func modelAction(_ manifest: ModelManifest, importURL: URL? = nil, verify: Bool = false) {
        guard modelOperation==nil, state == .idle else { return }
        modelOperation=manifest.id; modelProgress[manifest.id]=0
        Task {
            do {
                let progress: @Sendable (Double) async -> Void = { [self] value in await self.updateProgress(manifest.id,value:value) }
                if verify { try await installer.verify(manifest,progress:progress); lastStatus="\(manifest.title) verified" }
                else { await speech.unload(); await writing.unload(); speechReady=false; writingReady=false; try await installer.install(manifest,importing:importURL,progress:progress) }
            } catch { self.error=error.localizedDescription }
            modelOperation=nil; refreshModels(); if !verify { await warmModels() }
        }
    }
    func removeModel(_ manifest: ModelManifest) {
        guard state == .idle, modelOperation==nil else { return }
        Task {
            await speech.unload(); await writing.unload(); speechReady=false; writingReady=false
            do { try FileManager.default.trashItem(at:FlowPaths.model(manifest.id),resultingItemURL:nil) } catch { self.error=error.localizedDescription }
            refreshModels(); await warmModels()
        }
    }
    private func updateProgress(_ id: String,value: Double) { modelProgress[id]=value }
    func preferencesChanged() { shortcuts.shortcut=data.preferences.shortcut; applyAppearance(); data.enforceRetention(); if data.preferences.alwaysShowBar { overlay?.show() } else if state == .idle { overlay?.hideUnlessPersistent() } }
    func applyAppearance() {
        NSApp.appearance=data.preferences.appearance == "light" ? NSAppearance(named:.aqua) : data.preferences.appearance == "dark" ? NSAppearance(named:.darkAqua) : nil
        NSApp.setActivationPolicy(data.preferences.showDock ? .regular : .accessory)
    }
    func exportData(to url: URL) { do { try store?.export(data,to:url); lastStatus="Local data exported" } catch { self.error=error.localizedDescription } }
    func importData(from url: URL) { do { if let restored=try store?.importData(from:url) { data=restored; preferencesChanged() } } catch { self.error=error.localizedDescription } }
    func revealData() { NSWorkspace.shared.open(FlowPaths.root) }
    func resizeRecordingBar(){overlay?.updateLayout()}
    func dragRecordingBar(){overlay?.dragToMouse()}
    func finishDraggingRecordingBar(){overlay?.finishDragging()}
    func resetRecordingBarPosition(){data.preferences.overlayX=nil;data.preferences.overlayY=nil;data.preferences.barCenterX=nil;data.preferences.barBottomY=nil;overlay?.resetPosition()}
    func openHub() { NSApp.activate(ignoringOtherApps:true); NotificationCenter.default.post(name:.openFarFlowHub,object:nil) }
}

extension Notification.Name { static let openFarFlowHub=Notification.Name("openFarFlowHub") }
