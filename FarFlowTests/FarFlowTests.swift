import XCTest
import AVFoundation
@testable import FarFlowCore

final class TextPipelineTests: XCTestCase {
    func testExactSnippetIgnoresFinalPunctuation() {
        let snippets=[VoiceSnippet(trigger:"my signature",expansion:"Faraz\nFar Flow")]
        XCTAssertEqual(TextPipeline.snippet("My signature.",snippets:snippets),"Faraz\nFar Flow")
        XCTAssertNil(TextPipeline.snippet("Please use my signature here",snippets:snippets))
        XCTAssertNil(TextPipeline.snippet("",snippets:[VoiceSnippet(trigger:"",expansion:"bad")]))
    }
    func testDictionaryUsesWholeUnicodeWords() {
        let words=[DictionaryEntry(word:"Far Flow",alias:"far flo"),DictionaryEntry(word:"ID",alias:"id")]
        XCTAssertEqual(TextPipeline.applyDictionary("Use far flo; valid_id stays.",entries:words,language:"en"),"Use Far Flow; valid_id stays.")
    }
    func testDictionaryIsLanguageScoped() {
        let words=[DictionaryEntry(word:"Praktijk",alias:"practice",language:.dutch)]
        XCTAssertEqual(TextPipeline.applyDictionary("practice",entries:words,language:"en"),"practice")
        XCTAssertEqual(TextPipeline.applyDictionary("practice",entries:words,language:"nl"),"Praktijk")
    }
    func testLongestDictionaryPhraseWins() {
        let words=[DictionaryEntry(word:"Far Flow",alias:"far flow"),DictionaryEntry(word:"Faraz",alias:"far")]
        XCTAssertEqual(TextPipeline.applyDictionary("far flow",entries:words,language:"en"),"Far Flow")
    }
    func testFillersDoNotDamageWords() {
        XCTAssertEqual(TextPipeline.lightRules("Um, send the number to the forum.",language:"en"),"send the number to the forum.")
        XCTAssertEqual(TextPipeline.lightRules("Ehm, stuur het voorstel vanmiddag.",language:"nl"),"stuur het voorstel vanmiddag.")
        XCTAssertEqual(TextPipeline.lightRules("The museum is open.",language:"en"),"The museum is open.")
    }
    func testNegationCannotDisappear() {
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"I do not want to cancel.",candidate:"I want to cancel."))
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"Ik wil niet annuleren.",candidate:"Ik wil annuleren."))
        XCTAssertTrue(TextPipeline.isSafeEdit(original:"I do not want to cancel.",candidate:"I do not want to cancel."))
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"I want to cancel.",candidate:"I do not want to cancel."))
    }
    func testNumbersAndIdentifiersProtected() {
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"Send 20.50 to alex@example.com using customer_id",candidate:"Send 25.00 to alex@example.com using customer_id"))
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"Use customer_id",candidate:"Use customer ID"))
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"Send 20 euros",candidate:"Send 120 euros"))
    }
    func testExplicitNumericSelfCorrections() {
        XCTAssertEqual(TextPipeline.resolveNumericCorrections("Let's meet at two, actually three."),"Let's meet at three.")
        XCTAssertEqual(TextPipeline.resolveNumericCorrections("Let's meet at 2. Actually 3."),"Let's meet at 3.")
        XCTAssertEqual(TextPipeline.resolveNumericCorrections("Laten we om twee uur afspreken, nee, om drie uur."),"Laten we om drie uur afspreken.")
        XCTAssertEqual(TextPipeline.resolveNumericCorrections("Send 20 euros today and 30 euros tomorrow."),"Send 20 euros today and 30 euros tomorrow.")
    }
    func testDictionaryNamesProtected() {
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"Send it to Faraz.",candidate:"Send it to Farid.",dictionary:[DictionaryEntry(word:"Faraz")]))
    }
    func testEnglishAndDutchLanguageDetection() {
        XCTAssertEqual(TextPipeline.detectedLanguage("Kunnen we de afspraak naar morgen verplaatsen?",preferred:.auto),"nl")
        XCTAssertEqual(TextPipeline.detectedLanguage("Can we move the appointment to tomorrow?",preferred:.auto),"en")
        XCTAssertEqual(TextPipeline.detectedLanguage("Hello",preferred:.dutch),"nl")
    }
    func testTranslationRejected() {
        XCTAssertFalse(TextPipeline.isSafeEdit(original:"Kunnen we de afspraak naar morgen verplaatsen zodat iedereen erbij kan zijn?",candidate:"Can we move the appointment to tomorrow so everyone can attend?"))
    }
    func testWordErrorRate() {
        XCTAssertEqual(TextPipeline.wordErrorRate(reference:"Hello, world!",hypothesis:"hello world"),0)
        XCTAssertEqual(TextPipeline.wordErrorRate(reference:"one two three",hypothesis:"one four three"),1.0/3,accuracy:0.0001)
        XCTAssertEqual(TextPipeline.wordErrorRate(reference:"",hypothesis:""),0)
    }
}

final class LocalStoreTests: XCTestCase {
    func testOlderPreferencesDecodeWithNewControls() throws {
        let encoded = try JSONEncoder().encode(Preferences())
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["pauseMediaDuringDictation", "overlayX", "overlayY"] { old.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(decoded.pauseMediaDuringDictation ?? true)
        XCTAssertNil(decoded.overlayX); XCTAssertNil(decoded.overlayY)
    }
    func testMediaPreferenceAndBarPositionPersist() throws {
        let store = try LocalStore(directory: directory); var data = UserData()
        data.preferences.pauseMediaDuringDictation = false
        data.preferences.overlayX = 24; data.preferences.overlayY = 800
        try store.save(data)
        let decoded = try store.load().preferences
        XCTAssertEqual(decoded.pauseMediaDuringDictation, false)
        XCTAssertEqual(decoded.overlayX, 24); XCTAssertEqual(decoded.overlayY, 800)
    }
    var directory: URL!
    override func setUpWithError() throws { directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:directory) }
    func testStoreRoundTripAndAtomicReplacement() throws {
        let store=try LocalStore(directory:directory)
        var data=UserData();data.dictionary=[DictionaryEntry(word:"Far Flow")];try store.save(data)
        XCTAssertEqual(try store.load().dictionary.first?.word,"Far Flow")
        data.snippets=[VoiceSnippet(trigger:"hello",expansion:"Hello world.")];try store.save(data)
        XCTAssertEqual(try store.load().snippets.count,1)
        XCTAssertEqual(try store.load().dictionary.count,1)
    }
    func testExportImportUsesPlainPortableJSON() throws {
        let store=try LocalStore(directory:directory);var data=UserData();data.notes=[ScratchNote(title:"Dutch",text:"Goedemorgen")]
        let output=directory.appendingPathComponent("backup.json");try store.export(data,to:output)
        let result=try store.importData(from:output);XCTAssertEqual(result.notes.first?.text,"Goedemorgen")
    }
    func testRetentionDeletesRawAndCleanedTogether() {
        var data=UserData();data.preferences.retention = .day
        data.history=[history(date:Date(timeIntervalSince1970:0)),history(date:.now)]
        data.enforceRetention();XCTAssertEqual(data.history.count,1)
        data.preferences.retention = .off;data.enforceRetention();XCTAssertTrue(data.history.isEmpty)
    }
    func testFutureSchemaFailsInsteadOfOverwriting() throws {
        let store=try LocalStore(directory:directory);var data=UserData();data.schemaVersion=999;try store.save(data)
        XCTAssertThrowsError(try store.load())
    }
    func testCorruptImportLeavesCurrentDataIntact() throws {
        let store=try LocalStore(directory:directory);var data=UserData();data.dictionary=[DictionaryEntry(word:"Keep")];try store.save(data)
        let broken=directory.appendingPathComponent("broken.json");try Data("not json".utf8).write(to:broken)
        XCTAssertThrowsError(try store.importData(from:broken));XCTAssertEqual(try store.load().dictionary.first?.word,"Keep")
    }
    func testStreamingHash() throws {
        let url=directory.appendingPathComponent("file");try Data("abc".utf8).write(to:url)
        XCTAssertEqual(try ModelInstaller.hash(url),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    private func history(date:Date)->HistoryItem{HistoryItem(createdAt:date,raw:"raw",text:"clean",language:"en",appName:"Test",duration:1,processingSeconds:1,outcome:"Inserted",cleanup:"None")}
}

final class AudioTests: XCTestCase {
    func testShortSpeechIsPaddedWithoutChangingTheWords() {
        let original = Array(repeating: Float(0.1), count: 2400)
        let padded = AudioIO.padMinimumSpeechLength(original)
        XCTAssertEqual(padded.count, 4800)
        XCTAssertEqual(Array(padded.prefix(2400)), original)
        XCTAssertTrue(padded.suffix(2400).allSatisfy { $0 == 0 })
        XCTAssertEqual(AudioIO.padMinimumSpeechLength(Array(repeating: 0.1, count: 5000)).count, 5000)
    }
    func testAccidentalTapDoesNotLoadTheRecognizer() async throws {
        let engine = LocalSpeechEngine()
        let result = try await engine.transcribe(samples: Array(repeating: 0.1, count: 1000), language: .auto)
        XCTAssertEqual(result, "")
    }
    func testResamplingPreservesDurationAndFiniteSamples() throws {
        let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:48000,channels:1,interleaved:false)!
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;buffer.frameLength=48000
        for i in 0..<48000 {buffer.floatChannelData![0][i]=Float(sin(Double(i)*2*Double.pi*440/48000))*0.1}
        let samples=try AudioIO.resample(buffer)
        XCTAssertEqual(samples.count,16000,accuracy:100);XCTAssertTrue(samples.allSatisfy(\.isFinite))
    }
    func testSilentSamplesDoNotLoadSpeechModel() async throws {
        let engine=LocalSpeechEngine()
        let result=try await engine.transcribe(samples:Array(repeating:0,count:16000),language:.auto)
        XCTAssertEqual(result,"")
    }
}

final class FnGestureTests: XCTestCase {
    func testHoldReleasesImmediately(){var g=FnGesture();XCTAssertEqual(g.press(at:0),[.start]);XCTAssertEqual(g.release(at:2),[.stop]);XCTAssertNil(g.pendingStopDeadline)}
    func testDoubleTapLocksUntilNextPress(){var g=FnGesture();XCTAssertEqual(g.press(at:0),[.start]);XCTAssertEqual(g.release(at:0.06),[]);XCTAssertEqual(g.press(at:0.18),[.lock]);XCTAssertEqual(g.release(at:0.24),[]);XCTAssertTrue(g.isLocked);XCTAssertEqual(g.expire(at:1),[]);XCTAssertEqual(g.press(at:3),[.stop]);XCTAssertEqual(g.release(at:3.1),[]);XCTAssertFalse(g.isLocked)}
    func testSingleTapWaitsOnlyForDoubleTapWindow(){var g=FnGesture();_ = g.press(at:0);_ = g.release(at:0.05);XCTAssertEqual(g.expire(at:0.2),[]);XCTAssertEqual(g.expire(at:0.41),[.stop])}
    func testCancelResetsPendingStop(){var g=FnGesture();_ = g.press(at:0);_ = g.release(at:0.05);g.reset();XCTAssertEqual(g.expire(at:1),[]);XCTAssertEqual(g.press(at:2),[.start])}
    func testDuplicatePressDoesNotStartTwice(){var g=FnGesture();XCTAssertEqual(g.press(at:0),[.start]);XCTAssertEqual(g.press(at:0.01),[]);XCTAssertEqual(g.release(at:1),[.stop])}
    func testHandsFreeButtonCanStopWithFn(){var g=FnGesture();g.lockRecording();XCTAssertTrue(g.isLocked);XCTAssertEqual(g.press(at:1),[.stop]);XCTAssertEqual(g.release(at:1.1),[])}
}

final class FastCleanupTests: XCTestCase {
    func testLightWorksWithoutAnyWritingModel() async throws {
        let engine=LocalCleanupEngine(modelDirectory:URL(fileURLWithPath:"/nonexistent-farflow-test-model"))
        let english=try await engine.cleanup("Um, let's meet at two, actually three.",level:.light,language:"en",style:.standard,dictionary:[],snippets:[],useAI:true)
        XCTAssertEqual(english.text,"let's meet at three.");XCTAssertEqual(english.method,"Fast local cleanup")
        let dutch=try await engine.cleanup("Ehm, laten we om twee uur afspreken, nee, om drie uur.",level:.light,language:"nl",style:.standard,dictionary:[],snippets:[],useAI:true)
        XCTAssertEqual(dutch.text,"laten we om drie uur afspreken.")
    }
    func testMediumRequiresTheInstalledLocalModel() async {
        let engine=LocalCleanupEngine(modelDirectory:URL(fileURLWithPath:"/nonexistent-farflow-test-model"))
        do {_ = try await engine.cleanup("Please review the document.",level:.medium,language:"en",style:.standard,dictionary:[],snippets:[],useAI:true);XCTFail("Medium must not fall back to a remote model")}catch{XCTAssertTrue(error.localizedDescription.contains("Install"))}
    }
}

final class RecordingBarGeometryTests:XCTestCase {
    func testExpansionKeepsTheSameCenterAndBottom() {
        let bounds=CGRect(x:0,y:0,width:1440,height:900)
        let idle=RecordingBarGeometry.frame(centerX:720,bottomY:20,expanded:false,bounds:bounds)
        let expanded=RecordingBarGeometry.frame(centerX:idle.midX,bottomY:idle.minY,expanded:true,bounds:bounds)
        XCTAssertEqual(idle.midX,expanded.midX);XCTAssertEqual(idle.minY,expanded.minY)
        XCTAssertEqual(idle.width,76);XCTAssertEqual(expanded.width,224)
    }
    func testBothSizesStayOnScreenNearEveryEdge() {
        let bounds=CGRect(x:-1920,y:0,width:1920,height:1080)
        for expanded in [false,true] {
            for point in [CGPoint(x:-4000,y:-4000),CGPoint(x:4000,y:4000)] {
                let frame=RecordingBarGeometry.frame(centerX:point.x,bottomY:point.y,expanded:expanded,bounds:bounds)
                XCTAssertTrue(bounds.contains(frame));XCTAssertGreaterThanOrEqual(frame.minX,bounds.minX+5)
            }
        }
    }
    func testNewOptionalPreferencesRoundTrip() throws {
        var prefs=Preferences();prefs.barCenterX=730;prefs.barBottomY=12;prefs.interfaceRevision=2
        let decoded=try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded,prefs)
    }
}
