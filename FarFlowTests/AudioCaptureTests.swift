import XCTest
import AVFoundation

@MainActor private final class FakeMicrophoneSession: MicrophoneSession {
    var receive: ((AVAudioPCMBuffer)->Void)?
    var failure: Error?
    var starts=0
    var stops=0
    var needsRecovery=false
    func start(deviceID:UInt32,receive:@escaping(AVAudioPCMBuffer)->Void) throws {
        starts += 1;self.receive=receive
        if let failure {throw failure}
    }
    func stop(){stops += 1}
    func owns(_ object:Any?) -> Bool {(object as? FakeMicrophoneSession) === self}
    func send(rate:Double,seconds:Double=0.1,value:Float=0.2) {
        let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:1,interleaved:false)!
        let count=AVAudioFrameCount(rate*seconds)
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:count)!
        buffer.frameLength=count
        buffer.floatChannelData![0].update(repeating:value,count:Int(count))
        receive?(buffer)
    }
}

final class AudioCaptureTests:XCTestCase {
    @MainActor func testDuplicateStartDoesNotInstallAnotherTap() throws {
        let input=FakeMicrophoneSession();var made=0
        let audio=AudioCapture{made += 1;return input}
        try audio.start(deviceID:0);try audio.start(deviceID:0)
        XCTAssertEqual(made,1);XCTAssertEqual(input.starts,1)
        audio.cancel();audio.cancel();XCTAssertEqual(input.stops,1)
    }
    @MainActor func testRepeatedCapturesUseFreshSessionsAndCurrentRate() throws {
        let first=FakeMicrophoneSession(),second=FakeMicrophoneSession();var made=0
        let audio=AudioCapture{defer{made += 1};return made==0 ? first:second}
        try audio.start(deviceID:0);first.send(rate:44100)
        XCTAssertEqual(audio.duration,0.1,accuracy:0.001)
        XCTAssertEqual(try audio.stop().count,1600,accuracy:30)
        try audio.start(deviceID:0);second.send(rate:48000)
        XCTAssertEqual(audio.duration,0.1,accuracy:0.001)
        XCTAssertEqual(try audio.stop().count,1600,accuracy:30)
        XCTAssertEqual(made,2);XCTAssertEqual(first.stops,1);XCTAssertEqual(second.stops,1)
    }
    @MainActor func testFailedStartCanBeRetriedWithoutStuckCapture() throws {
        let first=FakeMicrophoneSession(),second=FakeMicrophoneSession();var made=0
        first.failure=NSError(domain:"microphone",code:1)
        let audio=AudioCapture{defer{made += 1};return made==0 ? first:second}
        XCTAssertThrowsError(try audio.start(deviceID:0));XCTAssertEqual(first.stops,1)
        try audio.start(deviceID:0);second.send(rate:48000)
        XCTAssertGreaterThan(try audio.stop().count,0)
    }
    @MainActor func testLateOldTapCannotContaminateNextRecording() throws {
        let first=FakeMicrophoneSession(),second=FakeMicrophoneSession();var made=0
        let audio=AudioCapture{defer{made += 1};return made==0 ? first:second}
        try audio.start(deviceID:0);first.send(rate:44100);audio.cancel()
        try audio.start(deviceID:0);first.send(rate:44100,seconds:1);second.send(rate:48000)
        XCTAssertEqual(audio.duration,0.1,accuracy:0.001)
        XCTAssertEqual(try audio.stop().count,1600,accuracy:30)
    }
    @MainActor func testConfigurationChangesOnlyMatchActiveSession() throws {
        let input=FakeMicrophoneSession(),other=FakeMicrophoneSession()
        let audio=AudioCapture{input};try audio.start(deviceID:0)
        XCTAssertFalse(audio.needsRecovery(after:input)) // delayed startup notification
        input.needsRecovery=true
        XCTAssertTrue(audio.needsRecovery(after:input));XCTAssertFalse(audio.needsRecovery(after:other))
        audio.cancel();XCTAssertFalse(audio.needsRecovery(after:input))
    }
}
