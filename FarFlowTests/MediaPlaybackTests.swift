import XCTest

@MainActor private final class FakeMediaTransport: MediaTransport {
    var available = true
    var pid: Int32 = 42
    var playing = true
    var acceptsCommands = true
    var deferReads = false
    var reads: [(Int32, Bool) -> Void] = []
    var commands: [UInt32] = []
    var closed=false
    func close(){closed=true}
    func readState(_ completion: @escaping (Int32, Bool) -> Void) {
        if deferReads { reads.append(completion) } else { completion(pid, playing) }
    }
    func send(_ command: UInt32) -> Bool {
        commands.append(command)
        if acceptsCommands { playing = command == 0 }
        return acceptsCommands
    }
    func deliverReads() { let pending = reads; reads = []; pending.forEach { $0(pid, playing) } }
}

final class MediaPlaybackTests: XCTestCase {
    @MainActor func testPlayingMediaPausesAndResumesOnce() async {
        let transport = FakeMediaTransport(), session = UUID()
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: session, enabled: true); service.resume(session: session); service.resume(session: session)
        XCTAssertEqual(transport.commands, [1, 0])
    }
    @MainActor func testOriginallyPausedMediaStaysPaused() async {
        let transport = FakeMediaTransport(), session = UUID(); transport.playing = false
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: session, enabled: true); service.resume(session: session)
        XCTAssertTrue(transport.commands.isEmpty)
    }
    @MainActor func testChangedPlayerIsNotStarted() async {
        let transport = FakeMediaTransport(), session = UUID()
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: session, enabled: true); transport.pid = 99; service.resume(session: session)
        XCTAssertEqual(transport.commands, [1])
    }
    @MainActor func testCanceledRequestCannotPauseLater() async {
        let transport = FakeMediaTransport(), session = UUID(); transport.deferReads = true
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: session, enabled: true); service.resume(session: session); transport.deliverReads()
        XCTAssertTrue(transport.commands.isEmpty)
    }
    @MainActor func testOldSessionCannotResumeNewSession() async {
        let transport = FakeMediaTransport(), first = UUID(), second = UUID()
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: first, enabled: true); service.pause(session: second, enabled: true)
        service.resume(session: first); XCTAssertEqual(transport.commands, [1])
        service.resume(session: second); XCTAssertEqual(transport.commands, [1, 0])
    }
    @MainActor func testRejectedPauseDoesNotCreateResume() async {
        let transport = FakeMediaTransport(), session = UUID(); transport.acceptsCommands = false
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: session, enabled: true); service.resume(session: session)
        XCTAssertEqual(transport.commands, [1])
    }
    @MainActor func testDisabledSettingSendsNoCommands() async {
        let transport = FakeMediaTransport(), session = UUID()
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: session, enabled: false); service.resume(session: session)
        XCTAssertTrue(transport.commands.isEmpty)
    }
    @MainActor func testTerminationResumesOwnedPause() async {
        let transport = FakeMediaTransport(), session = UUID()
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: session, enabled: true); service.stop(); service.stop()
        XCTAssertEqual(transport.commands, [1, 0]);XCTAssertTrue(transport.closed)
    }
    @MainActor func testNewSessionKeepsOwnershipDuringPendingResume() async {
        let transport = FakeMediaTransport(), first = UUID(), second = UUID()
        let service = MediaPlaybackService(transport: transport)
        service.pause(session: first, enabled: true); transport.deferReads = true
        service.resume(session: first); service.pause(session: second, enabled: true); transport.deliverReads()
        XCTAssertEqual(transport.commands, [1])
        service.resume(session: second); transport.deliverReads()
        XCTAssertEqual(transport.commands, [1, 0])
    }
}
