import AppKit
import CoreAudio
import FarFlowCore

/// Poll on a utility queue. Some macOS versions do not deliver process-input
/// property change notifications reliably; a five-second metadata poll is small.
@MainActor final class MeetingMonitor {
    private let queue=DispatchQueue(label:"com.faraz.farflow.meeting-detection",qos:.utility)
    private var polling=false
    private var state=MeetingDetectionState()
    private var generation=0
    func reset() { generation += 1; state.reset() }
    func poll(canPrompt: Bool, completion: @escaping @MainActor (MeetingCandidate?, Set<String>?, String?) -> Void) {
        guard !polling else { return }; polling=true
        let run=generation
        let apps=NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let names=Dictionary(apps.compactMap { app -> (String,String)? in
            guard let id=app.bundleIdentifier else { return nil }; return (id,app.localizedName ?? id)
        },uniquingKeysWith: { first,_ in first })
        queue.async {
            let result=Result { try Self.activeInputs() }
            Task { @MainActor [weak self] in
                guard let self else { return }; self.polling=false
                guard run == self.generation else { return }
                switch result {
                case .success(let bundleIDs):
                    let running=Set(names.keys)
                    let active=Set(bundleIDs.compactMap { MeetingCandidate.owner(of:$0,among:running) })
                    let candidates=active.map { MeetingCandidate(bundleID:$0,name:names[$0] ?? $0) }
                    completion(self.state.observe(candidates,now:.now,canPrompt:canPrompt),active,nil)
                case .failure:
                    completion(nil,nil,"Meeting detection is unavailable. You can still start recording from Meetings.")
                }
            }
        }
    }
    nonisolated static func activeInputs() throws -> [String] {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyProcessObjectList,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size: UInt32=0
        let system=AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system,&address,0,nil,&size)==noErr else { throw FlowError.message("Audio process metadata unavailable.") }
        guard size>0 else { return [] }
        var objects=[AudioObjectID](repeating:0,count:Int(size)/MemoryLayout<AudioObjectID>.size)
        let status=objects.withUnsafeMutableBytes { AudioObjectGetPropertyData(system,&address,0,nil,&size,$0.baseAddress!) }
        guard status==noErr else { throw FlowError.message("Audio processes changed. Retry next poll.") }
        return objects.compactMap { object in
            var property=AudioObjectPropertyAddress(mSelector:kAudioProcessPropertyIsRunningInput,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var active: UInt32=0, bytes=UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object,&property,0,nil,&bytes,&active)==noErr, active != 0 else { return nil }
            property.mSelector=kAudioProcessPropertyBundleID
            var value: Unmanaged<CFString>?
            bytes=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(object,&property,0,nil,&bytes,&value)==noErr else { return nil }
            return value?.takeRetainedValue() as String?
        }
    }
}
