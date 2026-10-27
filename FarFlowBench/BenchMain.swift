import Foundation
import Darwin
import AVFoundation
import FarFlowCore
import WhisperKit

struct Clip: Codable { let id: String; let language: String; let reference: String; let path: String }
struct Measurement: Codable { let id: String; let language: String; let reference: String; let transcript: String; let seconds: Double; let wer: Double }

@main struct BenchMain {
    static func main() async {
        do { try await run() } catch { fputs("Far Flow benchmark error: \(error.localizedDescription)\n",stderr);exit(1) }
    }
    static func run() async throws {
        let args=Array(CommandLine.arguments.dropFirst())
        guard let command=args.first else { print("FarFlowBench speech|whisper|cleanup|stress|prepare-whisper <corpus.json> <output.json>");return }
        print("Starting \(command) using models at \(FlowPaths.models.path)");fflush(stdout)
        if command=="prepare-whisper" {
            let url=try await WhisperKit.download(variant:"openai_whisper-large-v3-v20240930_turbo_632MB",downloadBase:FlowPaths.models.appendingPathComponent("whisper-benchmark"))
            try url.path.write(to:FlowPaths.models.appendingPathComponent("whisper-benchmark-path.txt"),atomically:true,encoding:.utf8)
            print("Whisper model downloaded to \(url.path)");return
        }
        if command=="cleanup" || command=="cleanup-fast" {
            let engine=LocalCleanupEngine()
            let start=Date();if command != "cleanup-fast" {try await engine.load()};let load=Date().timeIntervalSince(start)
            let cases=[("en","Um, please send the updated proposal this afternoon."),("nl","Ehm, kun je het voorstel vanmiddag versturen?"),("en","I do not want to cancel the appointment."),("nl","Ik wil de afspraak niet annuleren."),("en","The total is 20.50 euros. Send it to alex@example.com."),("nl","Het bedrag is 20,50 euro. Stuur het naar alex@example.com."),("en","Let's meet at two, actually three."),("nl","Laten we om twee uur afspreken, nee, om drie uur.")]
            var rows:[[String:Any]]=[]
            for (language,input) in cases {
                let began=Date();let output=try await engine.cleanup(input,level:command=="cleanup-fast" ? .light:.medium,language:language,style:.standard,dictionary:[],snippets:[],useAI:true)
                rows.append(["language":language,"input":input,"output":output.text,"method":output.method,"reviewSuggested":output.reviewSuggested,"seconds":Date().timeIntervalSince(began)])
                print("\(language): \(output.text)")
            }
            let transformed=command=="cleanup-fast" ? "Not requested":try await engine.transform("Kunnen we de afspraak naar morgen verplaatsen?",kind:.english)
            let data:[String:Any]=["engine":"Qwen3-4B-Instruct-2507-4bit","loadSeconds":load,"cases":rows,"explicitTranslation":transformed,"peakResidentMB":memory()]
            try JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args.count>1 ? args[1]:"cleanup-results.json"),options:.atomic);return
        }
        guard args.count>=3 else {throw FlowError.message("Supply a corpus file and output file.")}
        let clips=try JSONDecoder().decode([Clip].self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
        let speech=LocalSpeechEngine();var whisper:WhisperKit?
        let began=Date()
        print("Loading model…");fflush(stdout)
        if command=="whisper" {
            let path=try String(contentsOf:FlowPaths.models.appendingPathComponent("whisper-benchmark-path.txt"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
            whisper=try await WhisperKit(WhisperKitConfig(modelFolder:path,verbose:false,prewarm:false,load:true,download:false))
        }else{try await speech.load()}
        let load=Date().timeIntervalSince(began)
        print("Model loaded in \(load) seconds");fflush(stdout)
        var rows:[Measurement]=[]
        let count=command=="stress" ? 200:clips.count
        for index in 0..<count {
            let clip=clips[index % clips.count];let start=Date();let text:String
            if let whisper {
                let options=DecodingOptions(task:.transcribe,language:clip.language=="auto" ? nil:clip.language,temperature:0,skipSpecialTokens:true,withoutTimestamps:true)
                text=try await whisper.transcribe(audioPath:clip.path,decodeOptions:options).map(\.text).joined().trimmingCharacters(in:.whitespacesAndNewlines)
            }else{
                text=try await speech.transcribe(file:URL(fileURLWithPath:clip.path),language:clip.language=="en" ? .english:clip.language=="nl" ? .dutch:.auto)
            }
            rows.append(Measurement(id:clip.id,language:clip.language,reference:clip.reference,transcript:text,seconds:Date().timeIntervalSince(start),wer:TextPipeline.wordErrorRate(reference:clip.reference,hypothesis:text)))
            print("\(index+1)/\(count) \(clip.id): \(text)");fflush(stdout)
        }
        let encoded=try JSONEncoder().encode(rows)
        let object=try JSONSerialization.jsonObject(with:encoded)
        let output:[String:Any]=["engine":command,"fixtureType":"macOS synthetic speech; not user voice","loadSeconds":load,"cases":object,"peakResidentMB":memory()]
        try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[2]),options:.atomic)
    }
    static func memory()->Double{var info=rusage();getrusage(RUSAGE_SELF,&info);return Double(info.ru_maxrss)/1048576}
}
