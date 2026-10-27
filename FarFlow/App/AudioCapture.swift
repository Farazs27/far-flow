import AVFoundation
import CoreAudio
import AudioToolbox
import FarFlowCore

struct InputDevice: Identifiable, Hashable {
    let id: UInt32
    let name: String
}

@MainActor protocol MicrophoneSession: AnyObject {
    func start(deviceID: UInt32, receive: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
    func owns(_ object: Any?) -> Bool
    var needsRecovery: Bool {get}
}

@MainActor private final class EngineMicrophoneSession: MicrophoneSession {
    private let engine = AVAudioEngine()
    func start(deviceID: UInt32, receive: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if let error=FFAudioEngineBridge.start(engine,deviceID:deviceID,handler:receive) { throw error }
    }
    func stop() { FFAudioEngineBridge.stop(engine) }
    func owns(_ object: Any?) -> Bool { (object as? AVAudioEngine) === engine }
    var needsRecovery: Bool {!engine.isRunning}
}

/// The render thread only touches this locked buffer, never application/UI state.
private final class CapturedAudio: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [Float] = []
    private var rate: Double = 48000
    private var level: Float = 0
    private var generation: UUID?
    var meter: Float { lock.lock(); defer { lock.unlock() }; return level }
    var duration: Double { lock.lock(); defer { lock.unlock() }; return Double(collected.count)/rate }
    func begin(_ id: UUID) { lock.lock();defer{lock.unlock()};generation=id;collected=[];level=0 }
    func append(_ buffer: AVAudioPCMBuffer, session: UUID) {
        guard let channels=buffer.floatChannelData, !buffer.format.isInterleaved,
              buffer.format.sampleRate>0,buffer.format.channelCount>0,buffer.frameLength>0 else{return}
        let count=Int(buffer.frameLength), channelCount=Int(buffer.format.channelCount)
        var samples=[Float](repeating:0,count:count)
        for c in 0..<channelCount { for i in 0..<count { samples[i] += channels[c][i]/Float(channelCount) } }
        let rms=sqrt(samples.reduce(0) { $0+$1*$1 }/Float(count))
        lock.lock();defer{lock.unlock()}
        guard generation==session else{return}
        if collected.isEmpty {rate=buffer.format.sampleRate}
        guard rate==buffer.format.sampleRate else{return}
        let remaining=max(0,Int(rate*300)-collected.count)
        collected.append(contentsOf:samples.prefix(remaining));level=min(1,rms*12)
    }
    func finish() -> ([Float],Double) {
        lock.lock();defer{lock.unlock()}
        generation=nil;let result=(collected,rate);collected=[];level=0;return result
    }
}

@MainActor final class AudioCapture {
    private let captured=CapturedAudio()
    private let makeSession: () -> MicrophoneSession
    private var session: MicrophoneSession?
    init(makeSession: @escaping () -> MicrophoneSession) {self.makeSession=makeSession}
    convenience init() {self.init(makeSession:{EngineMicrophoneSession()})}
    var meter: Float {captured.meter}
    var duration: Double {captured.duration}
    func needsRecovery(after object:Any?) -> Bool {session?.owns(object) == true && session?.needsRecovery == true}

    static func devices() -> [InputDevice] {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size: UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size)==noErr else { return [] }
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&ids)==noErr else { return [] }
        return ids.compactMap { id in
            var channels=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:kAudioDevicePropertyScopeInput,mElement:kAudioObjectPropertyElementMain)
            var streamSize: UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&channels,0,nil,&streamSize)==noErr, streamSize>0 else { return nil }
            var nameAddress=AudioObjectPropertyAddress(mSelector:kAudioObjectPropertyName,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var name: Unmanaged<CFString>?; var nameSize=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            _ = AudioObjectGetPropertyData(id,&nameAddress,0,nil,&nameSize,&name)
            return InputDevice(id:id,name:(name?.takeRetainedValue() as String?) ?? "Microphone")
        }
    }
    func start(deviceID: UInt32) throws {
        guard session==nil else { return }
        let id=UUID(),next=makeSession();captured.begin(id)
        do {
            // A fresh graph prevents a previous capture's device format/tap surviving.
            try next.start(deviceID:deviceID) {[captured] buffer in captured.append(buffer,session:id)}
            session=next
        } catch {next.stop();_ = captured.finish();throw error}
    }
    func stop() throws -> [Float] {
        guard let current=session else { return [] }
        session=nil;current.stop()
        let (samples,sampleRate)=captured.finish()
        guard !samples.isEmpty, let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:sampleRate,channels:1,interleaved:false), let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)) else { return [] }
        buffer.frameLength=AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in if let base=ptr.baseAddress { buffer.floatChannelData?[0].update(from:base,count:samples.count) } }
        return try AudioIO.resample(buffer)
    }
    func cancel() {let current=session;session=nil;current?.stop();_ = captured.finish()}
}
