import Foundation

public enum MeetingSource: String, Codable, CaseIterable, Sendable {
    case microphone, system
    public var title: String { self == .microphone ? "Microphone" : "Meeting app" }
}
public enum MeetingStatus: String, Codable, Sendable { case recording, processing, complete, interrupted }
public struct MeetingSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var source: MeetingSource
    public var offset: Double
    public var duration: Double
    public var text: String
    public init(id: String, source: MeetingSource, offset: Double, duration: Double, text: String) {
        self.id=id; self.source=source; self.offset=offset; self.duration=duration; self.text=text
    }
}
public struct Meeting: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var title: String
    public var startedAt = Date()
    public var endedAt: Date?
    public var status: MeetingStatus = .recording
    public var sourceName: String
    public var language: DictationLanguage
    public var segments: [MeetingSegment] = []
    public var notes = ""
    public var summary = ""
    public var summaryDate: Date?
    public var issue: String?
    public init(title: String, sourceName: String, language: DictationLanguage) {
        self.title=title; self.sourceName=sourceName; self.language=language
    }
    public var orderedSegments: [MeetingSegment] {
        segments.sorted { $0.offset == $1.offset ? $0.id < $1.id : $0.offset < $1.offset }
    }
    public var transcript: String {
        orderedSegments.enumerated().filter { !$0.element.text.isEmpty }.map { index, segment in
            "[\(index+1)] \(Self.timestamp(segment.offset)) · \(segment.source.title)\n\(segment.text)"
        }.joined(separator: "\n\n")
    }
    public var summaryLanguage: DictationLanguage {
        guard language == .auto else { return language }
        // Detect speech, not the English source labels added by the UI.
        return TextPipeline.detectedLanguage(orderedSegments.map(\.text).joined(separator:"\n"),preferred:.auto) == "nl" ? .dutch : .english
    }
    public var exportText: String {
        "\(title)\n\(startedAt.formatted()) · \(sourceName)\n\nSUMMARY\n\(summary)\n\nNOTES\n\(notes)\n\nTRANSCRIPT\n\(transcript)"
    }
    public static func timestamp(_ seconds: Double) -> String {
        let value=max(0,Int(seconds)); return String(format:"%02d:%02d",value/60,value%60)
    }
    /// Chunk filenames are stable identities. Replaying after a crash cannot duplicate a segment.
    public mutating func checkpoint(_ segment: MeetingSegment) {
        guard !segments.contains(where: { $0.id == segment.id }) else { return }
        segments.append(segment)
    }
}

/// A bounded disk queue, not an audio archive. Delete each chunk only after its
/// transcript checkpoint commits. Filenames carry the source, offset and identity.
public struct MeetingAudioSpool: Sendable {
    public static let sampleRate = 16000
    public static let chunkSamples = sampleRate * 30
    public static let maximumPendingChunks = 40
    public let directory: URL
    public struct Chunk: Identifiable, Sendable {
        public var id: String { url.lastPathComponent }
        public let url: URL
        public let source: MeetingSource
        public let offset: Double
    }
    public init(meetingID: UUID, root: URL = FlowPaths.root) {
        directory=root.appendingPathComponent("MeetingAudio",isDirectory:true).appendingPathComponent(meetingID.uuidString,isDirectory:true)
    }
    public func pending() throws -> [Chunk] {
        guard FileManager.default.fileExists(atPath:directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).compactMap { url in
            guard url.pathExtension == "f32" else { return nil }
            let parts=url.deletingPathExtension().lastPathComponent.split(separator:"_")
            guard parts.count == 3, let source=MeetingSource(rawValue:String(parts[0])),
                  let frame=Double(parts[1]), frame.isFinite, frame>=0, UUID(uuidString:String(parts[2])) != nil else { return nil }
            return Chunk(url:url,source:source,offset:frame/16000)
        }.sorted { $0.offset == $1.offset ? $0.id < $1.id : $0.offset < $1.offset }
    }
    @discardableResult public func write(_ samples: [Float], source: MeetingSource, offset: Double) throws -> Chunk {
        guard !samples.isEmpty, samples.count <= Self.chunkSamples, offset.isFinite, offset >= 0 else {
            throw FlowError.message("Invalid meeting audio chunk.")
        }
        // The source and sample offset are stable across a failed write/retry.
        let url=directory.appendingPathComponent("\(source.rawValue)_\(Int(offset*16000))_\(directory.lastPathComponent).f32")
        let count=try pending().count
        guard FileManager.default.fileExists(atPath:url.path) || count < Self.maximumPendingChunks else {
            throw FlowError.message("Transcription cannot keep up. Recording stopped; saved audio can be finished locally.")
        }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let bytes=samples.withUnsafeBytes { Data($0) }
        try bytes.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        return Chunk(url:url,source:source,offset:offset)
    }
    public func samples(_ chunk: Chunk) throws -> [Float] {
        let bytes=try Data(contentsOf:chunk.url)
        guard bytes.count > 0, bytes.count % MemoryLayout<Float>.size == 0,
              bytes.count <= Self.chunkSamples * MemoryLayout<Float>.size else { throw FlowError.message("A saved meeting audio chunk is damaged.") }
        let result=bytes.withUnsafeBytes { raw in
            stride(from:0,to:raw.count,by:4).map { raw.loadUnaligned(fromByteOffset:$0,as:Float.self) }
        }
        guard result.allSatisfy(\.isFinite) else { throw FlowError.message("A saved meeting audio chunk contains invalid samples.") }
        return result
    }
    public func remove(_ chunk: Chunk) throws { try FileManager.default.removeItem(at:chunk.url) }
    public func removeAll() throws {
        if FileManager.default.fileExists(atPath:directory.path) { try FileManager.default.removeItem(at:directory) }
    }
}

/// One instance per source, owned by the capture callback queue. Memory is bounded
/// by thirty seconds even for multi-hour calls. Gaps retain their real timestamps.
public struct MeetingChunkBuffer {
    public private(set) var samples: [Float] = []
    private var offset: Double = 0
    public init() {}
    public mutating func append(_ incoming: [Float], at time: Double, emit: ([Float],Double) throws -> Void) throws {
        if !samples.isEmpty, abs(time - (offset + Double(samples.count)/16000)) > 0.25 { try flush(emit:emit) }
        var consumed=0
        while consumed < incoming.count {
            if samples.isEmpty { offset=time+Double(consumed)/16000 }
            let count=min(MeetingAudioSpool.chunkSamples-samples.count,incoming.count-consumed)
            samples.append(contentsOf:incoming[consumed..<consumed+count]); consumed += count
            if samples.count == MeetingAudioSpool.chunkSamples { try flush(emit:emit) }
        }
    }
    public mutating func flush(emit: ([Float],Double) throws -> Void) throws {
        guard !samples.isEmpty else { return }
        try emit(samples,offset)
        samples.removeAll(keepingCapacity:true)
    }
}

public enum MeetingSummary {
    public static let inputLimit = 6000
    public static func batches(_ text: String) -> [String] {
        // Keep all content, including a single unusually long transcript segment.
        var result: [String]=[], current=""
        for line in text.components(separatedBy:"\n") {
            var remainder=line
            while !remainder.isEmpty {
                let room=inputLimit-current.count-1
                if room<=0 { result.append(current); current=""; continue }
                let piece=String(remainder.prefix(room)); remainder.removeFirst(piece.count)
                current += piece
                if !remainder.isEmpty { result.append(current); current="" }
            }
            if current.count < inputLimit { current += "\n" }
        }
        if !current.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { result.append(current) }
        return result
    }
}

/// Anchor each input's timestamp domain to the same capture clock. Microphones
/// and system audio need not use the same timestamp epoch; device restarts may reset it.
public struct MeetingAudioClock {
    private var first: Double?
    private var arrival: Double = 0
    private var last: Double?
    public init() {}
    public mutating func offset(timestamp: Double, arrivedAt: Double) -> Double? {
        guard timestamp.isFinite, arrivedAt.isFinite, timestamp != last else { return nil }
        if first == nil || timestamp < (last ?? timestamp) { first=timestamp; arrival=max(0,arrivedAt) }
        last=timestamp
        return max(0,arrival+timestamp-(first ?? timestamp))
    }
}
