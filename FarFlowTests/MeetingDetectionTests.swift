import XCTest
@testable import FarFlowCore

final class MeetingDetectionTests: XCTestCase {
    let zoom=MeetingCandidate(bundleID:"us.zoom.xos",name:"Zoom")
    let epoch=Date(timeIntervalSince1970:1000)
    func testShortMicrophoneCheckDoesNotPromptAndContinuousUsePromptsOnce() {
        var state=MeetingDetectionState()
        XCTAssertNil(state.observe([zoom],now:epoch,canPrompt:true))
        XCTAssertNil(state.observe([],now:epoch.addingTimeInterval(4),canPrompt:true))
        XCTAssertNil(state.observe([zoom],now:epoch.addingTimeInterval(6),canPrompt:true))
        XCTAssertEqual(state.observe([zoom],now:epoch.addingTimeInterval(12),canPrompt:true),zoom)
        XCTAssertNil(state.observe([zoom],now:epoch.addingTimeInterval(30),canPrompt:true))
    }
    func testBusyWorkDefersPromptWithoutConsumingIt() {
        var state=MeetingDetectionState()
        _ = state.observe([zoom],now:epoch,canPrompt:false)
        XCTAssertNil(state.observe([zoom],now:epoch.addingTimeInterval(10),canPrompt:false))
        XCTAssertEqual(state.observe([zoom],now:epoch.addingTimeInterval(15),canPrompt:true),zoom)
    }
    func testMutedMicrophoneDoesNotPromptAgainUntilQuietInterval() {
        var state=MeetingDetectionState()
        _ = state.observe([zoom],now:epoch,canPrompt:true)
        _ = state.observe([zoom],now:epoch.addingTimeInterval(6),canPrompt:true)
        _ = state.observe([],now:epoch.addingTimeInterval(20),canPrompt:true)
        XCTAssertNil(state.observe([zoom],now:epoch.addingTimeInterval(30),canPrompt:true))
        XCTAssertNil(state.observe([zoom],now:epoch.addingTimeInterval(40),canPrompt:true))
        _ = state.observe([],now:epoch.addingTimeInterval(140),canPrompt:true)
        XCTAssertNil(state.observe([zoom],now:epoch.addingTimeInterval(150),canPrompt:true))
        XCTAssertEqual(state.observe([zoom],now:epoch.addingTimeInterval(156),canPrompt:true),zoom)
    }
    func testHelperAttributionRequiresKnownRunningOwnerAndExactPrefix() {
        let running:Set<String>=["com.google.Chrome","com.apple.Safari"]
        XCTAssertEqual(MeetingCandidate.owner(of:"com.google.Chrome.helper",among:running),"com.google.Chrome")
        XCTAssertNil(MeetingCandidate.owner(of:"com.google.ChromeEvil",among:running))
        XCTAssertNil(MeetingCandidate.owner(of:"com.apple.WebKit.WebContent",among:running))
        XCTAssertNil(MeetingCandidate.owner(of:"us.zoom.xos",among:running))
        XCTAssertNil(MeetingCandidate.owner(of:"com.faraz.farflow",among:running))
    }
    func testMeetingLanguageUsesSpeechAndExplicitOverride() {
        var value=Meeting(title:"English title",sourceName:"Meeting app",language:.auto)
        value.segments=[MeetingSegment(id:"1",source:.system,offset:0,duration:30,text:"We hebben besloten de proef maandag te starten. Noor stuurt vrijdag het voorstel. Het budget blijft tweehonderd euro en de locatie is nog niet bepaald.")]
        XCTAssertEqual(value.summaryLanguage,.dutch)
        value.language = .english
        XCTAssertEqual(value.summaryLanguage,.english)
        value.language = .auto
        value.segments[0].text="We agreed to launch the pilot on Monday. Alex will send the draft on Friday. The venue is still undecided."
        XCTAssertEqual(value.summaryLanguage,.english)
    }
    func testMemoryProfileKeepsOneModelAndUsesManualSummariesOnSmallerMacs() {
        XCTAssertFalse(HardwareProfile(memoryBytes:8*1024*1024*1024).automaticSummaries)
        XCTAssertTrue(HardwareProfile(memoryBytes:16*1024*1024*1024).automaticSummaries)
    }
    func testEndReminderRequiresObservedInputAndDoesNotTreatMuteAsAnAutomaticStop() {
        var reminder=MeetingEndReminder(); let id=UUID()
        XCTAssertFalse(reminder.observe(session:id,sourceActive:false,now:epoch))
        XCTAssertFalse(reminder.observe(session:id,sourceActive:false,now:epoch.addingTimeInterval(200)))
        XCTAssertFalse(reminder.observe(session:id,sourceActive:true,now:epoch.addingTimeInterval(210)))
        XCTAssertFalse(reminder.observe(session:id,sourceActive:false,now:epoch.addingTimeInterval(250)))
        XCTAssertTrue(reminder.observe(session:id,sourceActive:false,now:epoch.addingTimeInterval(300)))
        XCTAssertFalse(reminder.observe(session:id,sourceActive:false,now:epoch.addingTimeInterval(400)))
    }
    func testNewSessionResetsEndReminder() {
        var reminder=MeetingEndReminder()
        _ = reminder.observe(session:UUID(),sourceActive:true,now:epoch)
        XCTAssertFalse(reminder.observe(session:UUID(),sourceActive:false,now:epoch.addingTimeInterval(200)))
        XCTAssertFalse(reminder.observe(session:nil,sourceActive:false,now:epoch.addingTimeInterval(400)))
    }
}
