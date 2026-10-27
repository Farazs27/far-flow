import Foundation

public enum DictationLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto, english, dutch
    public var id: String { rawValue }
    public var title: String { switch self { case .auto: "Auto"; case .english: "English"; case .dutch: "Dutch" } }
    public var code: String { switch self { case .auto: "auto"; case .english: "en"; case .dutch: "nl" } }
}

public enum CleanupLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, light, medium
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var detail: String {
        switch self { case .none: "Recognized words, unchanged"; case .light: "Fast cleanup, punctuation, and spoken corrections"; case .medium: "AI edits for grammar, tone, and clarity" }
    }
}

public enum WritingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard, casual, professional
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum HistoryRetention: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, day, month, forever
    public var id: String { rawValue }
    public var title: String { switch self { case .off: "Off"; case .day: "24 hours"; case .month: "30 days"; case .forever: "Keep" } }
    public var interval: TimeInterval? { switch self { case .off: 0; case .day: 86400; case .month: 2592000; case .forever: nil } }
}

public struct DictionaryEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var word: String
    public var alias: String
    public var language: DictationLanguage
    public init(id: UUID = UUID(), word: String, alias: String = "", language: DictationLanguage = .auto) {
        self.id = id; self.word = word; self.alias = alias; self.language = language
    }
}

public struct VoiceSnippet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var trigger: String
    public var expansion: String
    public init(id: UUID = UUID(), trigger: String, expansion: String) { self.id = id; self.trigger = trigger; self.expansion = expansion }
}

public struct AppStyle: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var appName: String
    public var bundleID: String
    public var style: WritingStyle
    public init(id: UUID = UUID(), appName: String, bundleID: String, style: WritingStyle) { self.id = id; self.appName = appName; self.bundleID = bundleID; self.style = style }
}

public struct ScratchNote: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String = "Untitled note", text: String = "", updatedAt: Date = .now) { self.id = id; self.title = title; self.text = text; self.updatedAt = updatedAt }
}

public struct HistoryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var raw: String
    public var text: String
    public var language: String
    public var appName: String
    public var duration: Double
    public var processingSeconds: Double
    public var outcome: String
    public var cleanup: String
    public init(id: UUID = UUID(), createdAt: Date = .now, raw: String, text: String, language: String, appName: String, duration: Double, processingSeconds: Double, outcome: String, cleanup: String) {
        self.id=id; self.createdAt=createdAt; self.raw=raw; self.text=text; self.language=language; self.appName=appName; self.duration=duration; self.processingSeconds=processingSeconds; self.outcome=outcome; self.cleanup=cleanup
    }
    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var language: DictationLanguage = .auto
    public var cleanup: CleanupLevel = .light
    public var style: WritingStyle = .standard
    public var retention: HistoryRetention = .month
    public var useLocalAI = true
    public var shortcut = "fn"
    public var inputDeviceID: UInt32 = 0
    public var sounds = true
    public var showDock = true
    public var alwaysShowBar = false
    public var onboardingComplete = false
    public var showWelcome = true
    public var appearance = "system"
    // Optional additions decode older preference documents without a destructive migration.
    public var pauseMediaDuringDictation: Bool?
    public var overlayX: Double?
    public var overlayY: Double?
    public var barCenterX: Double?
    public var barBottomY: Double?
    public var interfaceRevision: Int?
    public init() {}
}

public struct UserData: Codable, Sendable {
    public var schemaVersion = 1
    public var preferences = Preferences()
    public var dictionary: [DictionaryEntry] = [DictionaryEntry(word:"Far Flow",alias:"farflow")]
    public var snippets: [VoiceSnippet] = []
    public var appStyles: [AppStyle] = []
    public var notes: [ScratchNote] = []
    public var history: [HistoryItem] = []
    public init() {}
    public mutating func enforceRetention(now: Date = .now) {
        guard let interval = preferences.retention.interval else { return }
        history.removeAll { interval == 0 || $0.createdAt < now.addingTimeInterval(-interval) }
    }
}

public enum FlowPaths {
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["FAR_FLOW_DATA_DIR"] { return URL(fileURLWithPath: override, isDirectory: true) }
        if let preview = Bundle.main.object(forInfoDictionaryKey:"FarFlowDemoDataDirectory") as? String {
            return URL(fileURLWithPath:preview,isDirectory:true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FarFlow", isDirectory: true)
    }
    public static var models: URL { root.appendingPathComponent("Models", isDirectory: true) }
    public static func model(_ id: String) -> URL { models.appendingPathComponent(id, isDirectory: true) }
}

public enum FlowError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let text): text } }
}
