import Foundation
import CryptoKit

public struct ModelFile: Codable, Sendable {
    public let path: String
    public let sha256: String
    public let bytes: Int64
}
public struct ModelManifest: Codable, Identifiable, Sendable {
    public let id: String
    public let repository: String
    public let revision: String
    public let license: String
    public let files: [ModelFile]
    public var byteCount: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var title: String { id == "parakeet-v3" ? "English + Dutch speech" : "Local writing model" }
    public func isInstalled() -> Bool {
        let folder = FlowPaths.model(id)
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("farflow-model.json").path) else { return false }
        return files.allSatisfy { file in
            let attributes = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(file.path).path)
            return (attributes?[.size] as? NSNumber)?.int64Value == file.bytes
        }
    }
}

public actor ModelInstaller {
    public init() {}
    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var sha = SHA256()
        while let data = try handle.read(upToCount: 4*1024*1024), !data.isEmpty { sha.update(data: data) }
        return sha.finalize().map { String(format:"%02x",$0) }.joined()
    }
    public func verify(_ manifest: ModelManifest, progress: @Sendable (Double) async -> Void) async throws {
        for (i,file) in manifest.files.enumerated() {
            try Task.checkCancellation()
            guard try Self.hash(FlowPaths.model(manifest.id).appendingPathComponent(file.path)) == file.sha256 else { throw FlowError.message("Model integrity check failed: \(file.path). Reinstall this model.") }
            await progress(Double(i+1)/Double(manifest.files.count))
        }
    }
    public func install(_ manifest: ModelManifest, importing source: URL? = nil, progress: @Sendable (Double) async -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: FlowPaths.models, withIntermediateDirectories: true)
        let staging = FlowPaths.models.appendingPathComponent(".\(manifest.id)-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var done: Int64=0
        for file in manifest.files {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(file.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let existing=FlowPaths.model(manifest.id).appendingPathComponent(file.path)
            if fm.fileExists(atPath: existing.path), (try? Self.hash(existing)) == file.sha256 {
                try fm.copyItem(at: existing, to: destination)
            } else if let source {
                try fm.copyItem(at: source.appendingPathComponent(file.path), to: destination)
            } else {
                guard let url=URL(string:"https://huggingface.co/\(manifest.repository)/resolve/\(manifest.revision)/\(file.path)") else { throw FlowError.message("Invalid model download address.") }
                let (temporary,response)=try await URLSession.shared.download(from:url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FlowError.message("Model download failed. Try again when connected.") }
                try fm.moveItem(at:temporary,to:destination)
            }
            guard try Self.hash(destination) == file.sha256 else { throw FlowError.message("Downloaded model checksum did not match. Installation was canceled.") }
            done += file.bytes; await progress(Double(done)/Double(manifest.byteCount))
        }
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("farflow-model.json"), options: .atomic)
        let final=FlowPaths.model(manifest.id)
        if fm.fileExists(atPath: final.path) { _ = try fm.replaceItemAt(final, withItemAt: staging) }
        else { try fm.moveItem(at: staging,to:final) }
    }
}
