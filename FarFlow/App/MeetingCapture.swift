import AppKit
import AVFoundation
import CoreAudio
import ScreenCaptureKit
import FarFlowCore

struct MeetingAppChoice: Identifiable {
    var id: String
    var name: String
    static var running: [Self] {
        var seen=Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id=app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return Self(id:id,name:app.localizedName ?? id)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// ScreenCaptureKit owns both audio inputs. No video output is attached or saved.
@MainActor final class MeetingCapture {
    private var stream: SCStream?
    private let output: MeetingAudioOutput
    var levels: (microphone: Float, system: Float) { output.levels }
    init(spool: MeetingAudioSpool, onFailure: @escaping @MainActor (String) -> Void) {
        output=MeetingAudioOutput(spool:spool,onFailure:onFailure)
    }
    func start(appBundleID: String, deviceID: UInt32) async throws {
        let content=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:false)
        try Task.checkCancellation()
        guard let display=content.displays.first else { throw FlowError.message("No display is available for system-audio capture.") }
        let filter: SCContentFilter
        if appBundleID.isEmpty {
            let ownApps=content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter=SCContentFilter(display:display,excludingApplications:ownApps,exceptingWindows:[])
        } else {
            let apps=content.applications.filter { $0.bundleIdentifier == appBundleID }
            guard !apps.isEmpty else { throw FlowError.message("Open the meeting app, refresh the list, and try again.") }
            filter=SCContentFilter(display:display,including:apps,exceptingWindows:[])
        }
        let configuration=SCStreamConfiguration()
        configuration.capturesAudio=true
        configuration.excludesCurrentProcessAudio=true
        configuration.sampleRate=16000; configuration.channelCount=1
        configuration.captureMicrophone=true
        if deviceID != 0 {
            var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyDeviceUID,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var uid: Unmanaged<CFString>?, size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID,&address,0,nil,&size,&uid)==noErr, let uid else {
                throw FlowError.message("The selected microphone is unavailable. Choose another input in Settings.")
            }
            configuration.microphoneCaptureDeviceID=uid.takeRetainedValue() as String
        }
        configuration.width=2; configuration.height=2
        configuration.minimumFrameInterval=CMTime(value:1,timescale:1)
        let next=SCStream(filter:filter,configuration:configuration,delegate:output)
        try next.addStreamOutput(output,type:.audio,sampleHandlerQueue:output.queue)
        try next.addStreamOutput(output,type:.microphone,sampleHandlerQueue:output.queue)
        stream=next; output.begin()
        do { try await next.startCapture(); try Task.checkCancellation() }
        catch { stop(); throw error }
        guard stream === next else { try? await next.stopCapture(); throw CancellationError() }
    }
    /// Flush on the serial callback queue before returning. Quit can now leave
    /// pending chunks for recovery without waiting for speech inference.
    @discardableResult func stop() -> String? {
        let issue=output.finish()
        let previous=stream; stream=nil
        if let previous { Task { try? await previous.stopCapture() } }
        return issue
    }
}

private final class MeetingAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue=DispatchQueue(label:"com.faraz.farflow.meeting-audio")
    private let spool: MeetingAudioSpool
    private let onFailure: @MainActor (String) -> Void
    private var accepting=false
    private var reportedFailure=false
    private var origin: Double=0
    private var buffers: [MeetingSource:MeetingChunkBuffer]=[:]
    private var converters: [MeetingSource:AVAudioConverter]=[:]
    private var clocks: [MeetingSource:MeetingAudioClock]=[:]
    private var meters: [MeetingSource:Float]=[:]
    var levels: (microphone:Float,system:Float) { queue.sync { (meters[.microphone] ?? 0,meters[.system] ?? 0) } }
    init(spool: MeetingAudioSpool, onFailure: @escaping @MainActor (String) -> Void) { self.spool=spool; self.onFailure=onFailure }
    func begin() { queue.sync { accepting=true; origin=CMClockGetTime(CMClockGetHostTimeClock()).seconds } }
    func finish() -> String? {
        queue.sync {
            accepting=false
            do {
                for source in MeetingSource.allCases {
                    try buffers[source]?.flush { samples,offset in _ = try spool.write(samples,source:source,offset:offset) }
                }
            } catch { report(error); meters=[:]; return error.localizedDescription }
            meters=[:]
            return nil
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [self] in
            guard accepting else { return }
            accepting=false; report(error)
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard accepting, sampleBuffer.isValid, type == .audio || type == .microphone else { return }
        let source: MeetingSource = type == .microphone ? .microphone : .system
        let pts=sampleBuffer.presentationTimeStamp.seconds
        if clocks[source] == nil { clocks[source]=MeetingAudioClock() }
        guard let offset=clocks[source]?.offset(timestamp:pts,arrivedAt:CMClockGetTime(CMClockGetHostTimeClock()).seconds-origin) else { return }
        do {
            try sampleBuffer.withAudioBufferList { list,_ in
                guard var description=sampleBuffer.formatDescription?.audioStreamBasicDescription,
                      let format=AVAudioFormat(streamDescription:&description),
                      let input=AVAudioPCMBuffer(pcmFormat:format,bufferListNoCopy:list.unsafePointer),
                      let target=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16000,channels:1,interleaved:false) else {
                    throw FlowError.message("Meeting audio has an unsupported format.")
                }
                if converters[source]?.inputFormat != format { converters[source]=AVAudioConverter(from:format,to:target) }
                guard let converter=converters[source],
                      let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:AVAudioFrameCount(Double(input.frameLength)*16000/format.sampleRate)+4096) else {
                    throw FlowError.message("Could not convert meeting audio.")
                }
                var delivered=false, conversionError: NSError?
                converter.convert(to:output,error:&conversionError) { _,status in
                    if delivered { status.pointee = .noDataNow; return nil }
                    delivered=true; status.pointee = .haveData; return input
                }
                if let conversionError { throw conversionError }
                guard let channel=output.floatChannelData?[0], output.frameLength>0 else { return }
                let samples=Array(UnsafeBufferPointer(start:channel,count:Int(output.frameLength)))
                meters[source]=min(1,sqrt(samples.reduce(0) { $0+$1*$1 }/Float(samples.count))*10)
                if buffers[source] == nil { buffers[source]=MeetingChunkBuffer() }
                try buffers[source]?.append(samples,at:offset) { samples,offset in
                    _ = try spool.write(samples,source:source,offset:offset)
                }
            }
        } catch { accepting=false; report(error) }
    }
    private func report(_ error: Error) {
        guard !reportedFailure else { return }; reportedFailure=true
        let message=error.localizedDescription
        Task { @MainActor [onFailure] in onFailure(message) }
    }
}
