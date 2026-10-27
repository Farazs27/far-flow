import AppKit
import Darwin

@MainActor protocol MediaTransport: AnyObject {
    var available: Bool { get }
    func readState(_ completion: @escaping (Int32, Bool) -> Void)
    func send(_ command: UInt32) -> Bool
    func close()
}
extension MediaTransport { func close() {} }

/// Local Now Playing transport. Uses explicit commands, never play/pause toggles.
@MainActor final class MediaPlaybackService {
    private let transport: MediaTransport
    private var timer: Timer?
    private var playing = false
    private var playerPID: Int32 = 0
    private var requestedSession: UUID?
    private var pausedOwner: (session: UUID, pid: Int32)?
    private var generation = 0
    var onChange: (() -> Void)?
    var status: String {
        guard transport.available else { return "Media control is unavailable on this macOS version" }
        if pausedOwner != nil { return "Playback paused for dictation" }
        if playing { return "Ready to pause \(NSRunningApplication(processIdentifier: playerPID)?.localizedName ?? "media")" }
        return "No media currently playing"
    }
    init(transport: MediaTransport? = nil) { self.transport = transport ?? LocalNowPlayingTransport() }
    func start() {
        timer?.invalidate(); refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil; requestedSession = nil; generation += 1
        // Termination cannot wait for an asynchronous query. Only resume our known owner.
        if let owner = pausedOwner, owner.pid == playerPID { _ = transport.send(0) }
        pausedOwner = nil
        transport.close()
    }
    private func refresh() {
        let revision = generation
        transport.readState { [weak self] pid, playing in
            guard let self, self.generation == revision else { return }
            self.playerPID = pid; self.playing = playing; self.onChange?()
        }
    }
    func pause(session: UUID, enabled: Bool) {
        guard enabled, transport.available else { return }
        generation += 1; requestedSession = session
        if let owner = pausedOwner { pausedOwner = (session, owner.pid); return }
        let revision = generation
        // Read afresh so a player paused just before Fn is never started afterward.
        transport.readState { [weak self] pid, playing in
            guard let self, self.generation == revision, self.requestedSession == session else { return }
            self.playerPID = pid; self.playing = playing
            if playing, pid > 0, self.transport.send(1) {
                self.pausedOwner = (session, pid); self.playing = false
            }
            self.onChange?()
        }
    }
    func resume(session: UUID) {
        guard requestedSession == session || pausedOwner?.session == session else { return }
        requestedSession = nil; generation += 1
        guard let owner = pausedOwner, owner.session == session else { return }
        let revision = generation
        transport.readState { [weak self] pid, playing in
            guard let self, self.generation == revision, self.pausedOwner?.session == session else { return }
            self.pausedOwner = nil; self.playerPID = pid; self.playing = playing
            if owner.pid == pid, self.transport.send(0) { self.playing = true }
            self.onChange?()
        }
    }
}

/// Bundled local helper: macOS 15.4+ restricts direct app reads of MediaRemote.
@MainActor final class LocalNowPlayingTransport: MediaTransport {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var pending: [UInt64: (Int32, Bool) -> Void] = [:]
    private var nextID: UInt64 = 1
    private var buffer = Data()
    private var running = false
    var available: Bool { running && process.isRunning }
    init() {
        guard let script = Bundle.main.url(forResource: "media-bridge", withExtension: "pl"),
              let frameworks = Bundle.main.privateFrameworksURL else { return }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, frameworks.appendingPathComponent("FarFlowMediaBridge.framework").path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in Task { @MainActor [weak self] in
            guard let self else { return }; self.running = false
            let callbacks = self.pending.values; self.pending.removeAll()
            callbacks.forEach { $0(0, false) }
        } }
        do { try process.run(); running = true } catch { output.fileHandleForReading.readabilityHandler = nil }
    }
    func readState(_ completion: @escaping (Int32, Bool) -> Void) {
        guard available else { completion(0, false); return }
        let id = nextID; nextID += 1; pending[id] = completion
        guard write("\(id) -1\n") else { pending.removeValue(forKey: id)?(0, false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.pending.removeValue(forKey: id)?(0, false) }
    }
    func send(_ command: UInt32) -> Bool {
        guard command <= 1, available else { return false }
        return write("0 \(command)\n")
    }
    private func write(_ value: String) -> Bool {
        do { try input.fileHandleForWriting.write(contentsOf: Data(value.utf8)); return true } catch { return false }
    }
    private func receive(_ data: Data) {
        guard !data.isEmpty else { output.fileHandleForReading.readabilityHandler = nil; return }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (value["id"] as? NSNumber)?.uint64Value,
                  let callback = pending.removeValue(forKey: id) else { continue }
            callback((value["pid"] as? NSNumber)?.int32Value ?? 0, value["playing"] as? Bool ?? false)
        }
        if buffer.count > 8192 { buffer.removeAll() }
    }
    func close() {
        // EOF is processed after queued transport commands, including the final resume.
        try? input.fileHandleForWriting.close()
    }
}
