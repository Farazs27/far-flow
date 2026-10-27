import AVFoundation
import CoreAudio
import AudioToolbox
import FarFlowCore

struct InputDevice: Identifiable, Hashable {
    let id: UInt32
    let name: String
}

final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var collected: [Float] = []
    private var rate: Double = 48000
    private var level: Float = 0
    private var active = false
    var meter: Float { lock.lock(); defer { lock.unlock() }; return level }
    var duration: Double { lock.lock(); defer { lock.unlock() }; return Double(collected.count)/rate }

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
        guard !active else { return }
        let input=engine.inputNode
        if let unit=input.audioUnit {
            var device=deviceID
            if device==0 {
                var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultInputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
                var size=UInt32(MemoryLayout<UInt32>.size)
                guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device)==noErr else {throw FlowError.message("The system microphone is unavailable.")}
            }
            guard AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&device,UInt32(MemoryLayout<UInt32>.size))==noErr else { throw FlowError.message("This microphone is unavailable. Choose another input in Settings.") }
        }
        let format=input.outputFormat(forBus:0)
        guard format.sampleRate>0, format.channelCount>0 else { throw FlowError.message("No microphone input is available.") }
        lock.lock(); collected=[]; rate=format.sampleRate; level=0; lock.unlock()
        input.installTap(onBus:0,bufferSize:2048,format:format) { [weak self] buffer,_ in
            guard let self, let channels=buffer.floatChannelData else { return }
            let count=Int(buffer.frameLength), channelCount=Int(buffer.format.channelCount)
            var samples=[Float](repeating:0,count:count)
            for c in 0..<channelCount { for i in 0..<count { samples[i] += channels[c][i]/Float(channelCount) } }
            let rms=sqrt(samples.reduce(0) { $0+$1*$1 }/Float(max(1,count)))
            self.lock.lock()
            if self.collected.count < Int(self.rate*300) { self.collected.append(contentsOf:samples) }
            self.level=min(1,rms*12)
            self.lock.unlock()
        }
        do { engine.prepare(); try engine.start(); active=true }
        catch { input.removeTap(onBus:0); throw error }
    }
    func stop() throws -> [Float] {
        guard active else { return [] }
        engine.stop(); engine.inputNode.removeTap(onBus:0); active=false
        lock.lock(); let samples=collected; let sampleRate=rate; collected=[]; level=0; lock.unlock()
        guard !samples.isEmpty, let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:sampleRate,channels:1,interleaved:false), let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)) else { return [] }
        buffer.frameLength=AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ptr in if let base=ptr.baseAddress { buffer.floatChannelData?[0].update(from:base,count:samples.count) } }
        return try AudioIO.resample(buffer)
    }
    func cancel() { _ = try? stop() }
}
