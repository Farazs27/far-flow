import XCTest
@testable import FarFlowCore

final class MeetingTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent("FarFlow-Meetings-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:directory) }

    func testAnHourOfTwoSourceAudioHasBoundedBuffersAndNoRepeatedRanges() throws {
        let packet=Array(repeating:Float(0.25),count:16000)
        var microphone=MeetingChunkBuffer(), system=MeetingChunkBuffer()
        var micOffsets: [Double]=[], systemOffsets: [Double]=[], totalMic=0, totalSystem=0
        for second in 0..<3600 {
            try microphone.append(packet,at:Double(second)) { samples,offset in
                XCTAssertEqual(samples.count,480000); micOffsets.append(offset); totalMic += samples.count
            }
            try system.append(packet,at:Double(second)) { samples,offset in
                XCTAssertEqual(samples.count,480000); systemOffsets.append(offset); totalSystem += samples.count
            }
            XCTAssertLessThan(microphone.samples.count,480000); XCTAssertLessThan(system.samples.count,480000)
        }
        XCTAssertEqual(totalMic,3600*16000); XCTAssertEqual(totalSystem,totalMic)
        XCTAssertEqual(micOffsets,stride(from:0.0,to:3600,by:30).map{$0})
        XCTAssertEqual(systemOffsets,micOffsets)
        XCTAssertTrue(microphone.samples.isEmpty); XCTAssertTrue(system.samples.isEmpty)
    }
    func testIndependentAudioClocksAndTimestampResetKeepRealOffsets() {
        var microphone=MeetingAudioClock(), system=MeetingAudioClock()
        XCTAssertEqual(microphone.offset(timestamp:0,arrivedAt:0.1),0.1)
        XCTAssertEqual(system.offset(timestamp:9000,arrivedAt:0.2) ?? -1,0.2,accuracy:0.0001)
        XCTAssertEqual(microphone.offset(timestamp:30,arrivedAt:30.2) ?? -1,30.1,accuracy:0.0001)
        XCTAssertEqual(system.offset(timestamp:9030,arrivedAt:30.3) ?? -1,30.2,accuracy:0.0001)
        XCTAssertNil(microphone.offset(timestamp:30,arrivedAt:31))
        XCTAssertEqual(microphone.offset(timestamp:0,arrivedAt:40),40)
        XCTAssertNil(system.offset(timestamp:.nan,arrivedAt:41))
    }
    func testGapsAndFinalPartialChunksKeepTheirOffsets() throws {
        var buffer=MeetingChunkBuffer(); var offsets: [Double]=[], counts: [Int]=[]
        let emit: ([Float],Double) throws -> Void = { samples,offset in offsets.append(offset); counts.append(samples.count) }
        try buffer.append(Array(repeating:0.2,count:16000),at:0,emit:emit)
        try buffer.append(Array(repeating:0.2,count:8000),at:10,emit:emit)
        try buffer.flush(emit:emit)
        try buffer.flush(emit:emit)
        XCTAssertEqual(offsets,[0,10]); XCTAssertEqual(counts,[16000,8000])
    }
    func testSpoolSurvivesRecreationAndPreservesSamples() throws {
        let id=UUID(), samples: [Float]=[0.1,-0.5,0.25,0]
        let first=MeetingAudioSpool(meetingID:id,root:directory)
        let chunk=try first.write(samples,source:.system,offset:42.125)
        let repeated=try first.write(samples,source:.system,offset:42.125)
        XCTAssertEqual(repeated.id,chunk.id)
        let reopened=MeetingAudioSpool(meetingID:id,root:directory)
        let pending=try reopened.pending()
        XCTAssertEqual(pending.count,1); XCTAssertEqual(pending[0].id,chunk.id)
        XCTAssertEqual(pending[0].offset,42.125); XCTAssertEqual(pending[0].source,.system)
        XCTAssertEqual(try reopened.samples(pending[0]),samples)
        try reopened.remove(pending[0]); XCTAssertTrue(try reopened.pending().isEmpty)
    }
    func testSpoolBackpressureStopsAtBoundWithoutDeletingPendingAudio() throws {
        let spool=MeetingAudioSpool(meetingID:UUID(),root:directory)
        for index in 0..<MeetingAudioSpool.maximumPendingChunks { try spool.write([0.1],source:.microphone,offset:Double(index)) }
        XCTAssertThrowsError(try spool.write([0.1],source:.microphone,offset:41))
        XCTAssertEqual(try spool.pending().count,MeetingAudioSpool.maximumPendingChunks)
    }
    func testRepeatedCheckpointDoesNotDuplicateTranscript() {
        var value=Meeting(title:"Review",sourceName:"Call",language:.auto)
        let segment=MeetingSegment(id:"stable",source:.microphone,offset:4,duration:2,text:"The budget is 20 euros.")
        value.checkpoint(segment); value.checkpoint(segment)
        XCTAssertEqual(value.segments.count,1)
        XCTAssertTrue(value.transcript.contains("[1] 00:04"))
    }
    func testMeetingAndEditedSummarySurviveHistoryRetentionAndBackup() throws {
        let store=try LocalStore(directory:directory)
        var value=Meeting(title:"Planning",sourceName:"Meet",language:.dutch)
        value.notes="Bespreek de planning"; value.summary="Geen besluit genomen."; value.status = .complete
        value.startedAt=Date(timeIntervalSince1970:100)
        var data=UserData(); data.preferences.retention = .off; data.meetings=[value]
        data.enforceRetention(); try store.save(data)
        let backup=directory.appendingPathComponent("backup.json"); try store.export(data,to:backup)
        let restored=try store.importData(from:backup)
        XCTAssertEqual(restored.meetings?.first?.summary,value.summary)
        XCTAssertEqual(try store.load().meetings?.first?.notes,value.notes)
        XCTAssertEqual(restored.schemaVersion,2)
    }
    func testVersionOneUpgradePreservesNotesAndCreatesSafetyBackup() throws {
        let store=try LocalStore(directory:directory)
        var old=UserData(); old.schemaVersion=1; old.createNote(text:"Keep my existing notes")
        try store.save(old)
        let updated=try store.load()
        XCTAssertEqual(updated.schemaVersion,2); XCTAssertEqual(updated.notes,old.notes); XCTAssertNil(updated.meetings)
        let backups=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{$0.lastPathComponent.hasPrefix("Before Meetings Upgrade")}
        XCTAssertEqual(backups.count,1)
        XCTAssertEqual(try store.importData(from:backups[0]).notes.first?.text,"Keep my existing notes")
    }
    func testSummaryBatchesIncludeEndOfLongEnglishDutchTranscript() {
        let text=String(repeating:"[1] 00:00 Microphone: Geen besluit genomen. No decision was made.\n",count:600)+"[99] Final decision: wait until Monday."
        let batches=MeetingSummary.batches(text)
        XCTAssertGreaterThan(batches.count,1)
        XCTAssertTrue(batches.allSatisfy { $0.count <= MeetingSummary.inputLimit })
        XCTAssertTrue(batches.last?.contains("wait until Monday") == true)
        XCTAssertEqual(batches.joined().filter{!$0.isWhitespace},text.filter{!$0.isWhitespace})
    }
    @MainActor func testRecoveryReplaysCheckpointWithoutDuplicatingAndDeletesAudioOnlyAfterSave() async throws {
        var value=Meeting(title:"Recovered",sourceName:"Call",language:.auto)
        let spool=MeetingAudioSpool(meetingID:value.id,root:directory)
        let chunk=try spool.write(Array(repeating:0,count:16000),source:.microphone,offset:0)
        value.checkpoint(MeetingSegment(id:chunk.id,source:.microphone,offset:0,duration:1,text:"Already saved"))
        let controller=MeetingController(speech:LocalSpeechEngine(),writing:LocalCleanupEngine(),audioRoot:directory)
        controller.lookup={ _ in value }
        controller.persist={ current in value=current; return true }
        controller.recover(value.id)
        for _ in 0..<100 where controller.busy { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertFalse(controller.busy); XCTAssertNil(controller.error)
        XCTAssertEqual(value.segments.count,1); XCTAssertEqual(value.status,.complete)
        XCTAssertTrue(try spool.pending().isEmpty)
    }
    @MainActor func testFailedCheckpointKeepsAudioForRetry() async throws {
        var value=Meeting(title:"Storage failure",sourceName:"Call",language:.auto)
        let spool=MeetingAudioSpool(meetingID:value.id,root:directory)
        try spool.write(Array(repeating:0,count:16000),source:.microphone,offset:0)
        let controller=MeetingController(speech:LocalSpeechEngine(),writing:LocalCleanupEngine(),audioRoot:directory)
        controller.lookup={ _ in value }
        var saves=0
        controller.persist={ current in saves += 1; if saves == 1 { value=current; return true }; return false }
        controller.recover(value.id)
        for _ in 0..<100 where controller.busy { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertFalse(controller.busy); XCTAssertNotNil(controller.error)
        XCTAssertEqual(try spool.pending().count,1)
    }
    @MainActor func testPauseLeavesPendingChunksAndDoesNotAcceptLateResult() async throws {
        var value=Meeting(title:"Pause",sourceName:"Call",language:.auto)
        let spool=MeetingAudioSpool(meetingID:value.id,root:directory)
        try spool.write(Array(repeating:0,count:16000),source:.system,offset:3)
        let controller=MeetingController(speech:LocalSpeechEngine(),writing:LocalCleanupEngine(),audioRoot:directory)
        controller.lookup={ _ in value }; controller.persist={ current in value=current; return true }
        controller.recover(value.id); controller.pauseProcessing()
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertFalse(controller.busy); XCTAssertEqual(value.status,.interrupted)
        XCTAssertTrue(value.segments.isEmpty); XCTAssertEqual(try spool.pending().count,1)
    }
}
