import Foundation

/// Metadata only: no audio, window titles, calendar or browser history.
public struct MeetingCandidate: Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public init(bundleID: String, name: String) { self.bundleID=bundleID; self.name=name }
    public static let supportedIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.cisco.webexmeetingsapp", "com.webex.meetingmanager", "com.apple.FaceTime",
        "com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.brave.Browser", "org.mozilla.firefox", "com.apple.Safari"
    ]
    public static func owner(of processBundleID: String, among running: Set<String>) -> String? {
        // Only attribute helpers of a known, currently running app. Shared WebKit
        // helpers cannot be attributed reliably and deliberately do not match.
        supportedIDs.sorted().first {
            running.contains($0) && (processBundleID == $0 || processBundleID.hasPrefix($0+"."))
        }
    }
}

/// Debounce short microphone checks and prompt once per usage session. A quiet
/// interval rearms prompts; it NEVER ends a recording (the user may be muted).
public struct MeetingDetectionState {
    private var firstSeen: [String: Date] = [:]
    private var lastSeen: [String: Date] = [:]
    private var prompted: Set<String> = []
    public init() {}
    public mutating func observe(_ candidates: [MeetingCandidate], now: Date, canPrompt: Bool) -> MeetingCandidate? {
        let active=Set(candidates.map(\.bundleID))
        for id in Array(lastSeen.keys) where !active.contains(id) {
            if now.timeIntervalSince(lastSeen[id]!) >= 90 {
                firstSeen[id]=nil; lastSeen[id]=nil; prompted.remove(id)
            } else { firstSeen[id]=nil }
        }
        for candidate in candidates {
            let id=candidate.bundleID
            if firstSeen[id] == nil { firstSeen[id]=now }
            lastSeen[id]=now
        }
        guard canPrompt else { return nil }
        for candidate in candidates.sorted(by: { $0.bundleID < $1.bundleID }) {
            if !prompted.contains(candidate.bundleID), let first=firstSeen[candidate.bundleID], now.timeIntervalSince(first)>=6 {
                prompted.insert(candidate.bundleID)
                return candidate
            }
        }
        return nil
    }
    public mutating func reset() { self=Self() }
}

/// A reminder only, never an automatic stop. Wait until this recording has
/// actually observed source input, so unidentifiable browser helpers stay quiet.
public struct MeetingEndReminder {
    private var session: UUID?
    private var lastInput: Date?
    private var shown=false
    public init() {}
    public mutating func observe(session id: UUID?, sourceActive: Bool, now: Date) -> Bool {
        if session != id { session=id; lastInput=nil; shown=false }
        guard id != nil else { return false }
        if sourceActive { lastInput=now; return false }
        guard !shown, let lastInput, now.timeIntervalSince(lastInput)>=90 else { return false }
        shown=true; return true
    }
}
