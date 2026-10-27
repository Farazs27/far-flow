import Foundation
import SQLite3

/// One transaction owns a complete versioned document. SQLite provides durable atomic replacement.
public final class LocalStore {
    private var database: OpaquePointer?
    public let url: URL
    public init(directory: URL = FlowPaths.root) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("farflow.sqlite")
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw FlowError.message("Far Flow could not open its local database.")
        }
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS documents (id INTEGER PRIMARY KEY, version INTEGER NOT NULL, body BLOB NOT NULL);")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    deinit { sqlite3_close(database) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw FlowError.message("The local database operation failed.") }
    }
    public func load() throws -> UserData {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT body FROM documents WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw FlowError.message("Could not read local data.") }
        guard sqlite3_step(statement) == SQLITE_ROW else { return UserData() }
        guard let bytes = sqlite3_column_blob(statement, 0) else { throw FlowError.message("The local data document is empty.") }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        var result = try JSONDecoder().decode(UserData.self, from: data)
        guard result.schemaVersion == 1 else { throw FlowError.message("This data was created by a newer Far Flow version. Export it before downgrading.") }
        result.enforceRetention()
        return result
    }
    public func save(_ value: UserData) throws {
        let data = try JSONEncoder().encode(value)
        try execute("BEGIN IMMEDIATE")
        do {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(database, "INSERT INTO documents(id,version,body) VALUES(1,1,?) ON CONFLICT(id) DO UPDATE SET version=1, body=excluded.body", -1, &statement, nil) == SQLITE_OK else { throw FlowError.message("Could not prepare local save.") }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let status = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
            guard status == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw FlowError.message("Could not save local data. Check available disk space.") }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    public func export(_ data: UserData, to destination: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(data).write(to: destination, options: .atomic)
    }
    public func importData(from source: URL) throws -> UserData {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var value = try decoder.decode(UserData.self, from: Data(contentsOf: source))
        guard value.schemaVersion == 1 else { throw FlowError.message("Unsupported export version.") }
        value.enforceRetention(); return value
    }
}
