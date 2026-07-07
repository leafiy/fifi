import Foundation
import CSQLite

public enum SQLValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

public struct DatabaseError: Error {
    public let code: Int32
    public let message: String
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// @unchecked: `handle` is only touched under `lock`.
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    // SQLite is opened FULLMUTEX, which serializes individual statements, but not
    // multi-statement transactions. The recursive lock makes transaction bodies
    // atomic with respect to every other caller on this connection.
    private let lock = NSRecursiveLock()

    public init(path: String) throws {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &opened, flags, nil)
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            if let opened {
                sqlite3_close(opened)
            }
            throw DatabaseError(code: result, message: message)
        }

        handle = opened
        do {
            try execute("PRAGMA journal_mode=WAL")
            // NORMAL under WAL still guarantees a corruption-free database
            // after a crash; only the very last commit may be lost.
            try execute("PRAGMA synchronous=NORMAL")
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA busy_timeout=2000")
            try registerRegexpFunction()
        } catch {
            close()
            throw error
        }
    }

    deinit {
        close()
    }

    // MARK: - Maintenance

    /// Runs `PRAGMA quick_check`; an empty result means the database is sound.
    public func integrityCheck() throws -> [String] {
        let rows = try query("PRAGMA quick_check", [])
        let issues = rows.compactMap { row -> String? in
            if case let .text(value)? = row["quick_check"] { return value }
            return nil
        }
        return issues == ["ok"] ? [] : issues
    }

    /// Copies the live database into a new file using the SQLite Online
    /// Backup API; safe while this connection stays in use.
    public func backup(toPath path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let source = try requireHandle()
        try Self.copy(from: source, toPath: path)
    }

    /// Replaces the contents of this database with the file at `path`,
    /// atomically from the perspective of other readers on this connection.
    public func restore(fromPath path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let destination = try requireHandle()
        var sourceHandle: OpaquePointer?
        let openResult = sqlite3_open_v2(path, &sourceHandle, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let sourceHandle else {
            if let sourceHandle { sqlite3_close(sourceHandle) }
            throw DatabaseError(code: openResult, message: "Unable to open backup at \(path)")
        }
        defer { sqlite3_close(sourceHandle) }
        try Self.runBackup(source: sourceHandle, destination: destination)
    }

    private static func copy(from source: OpaquePointer, toPath path: String) throws {
        var destinationHandle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let openResult = sqlite3_open_v2(path, &destinationHandle, flags, nil)
        guard openResult == SQLITE_OK, let destinationHandle else {
            if let destinationHandle { sqlite3_close(destinationHandle) }
            throw DatabaseError(code: openResult, message: "Unable to create backup at \(path)")
        }
        defer { sqlite3_close(destinationHandle) }
        try runBackup(source: source, destination: destinationHandle)
    }

    private static func runBackup(source: OpaquePointer, destination: OpaquePointer) throws {
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw DatabaseError(
                code: sqlite3_errcode(destination),
                message: String(cString: sqlite3_errmsg(destination))
            )
        }
        var busyRetries = 0
        var result = sqlite3_backup_step(backup, -1)
        while result == SQLITE_OK || ((result == SQLITE_BUSY || result == SQLITE_LOCKED) && busyRetries < 5) {
            if result != SQLITE_OK {
                busyRetries += 1
                Thread.sleep(forTimeInterval: 0.01)
            }
            result = sqlite3_backup_step(backup, -1)
        }
        sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE else {
            throw DatabaseError(
                code: result,
                message: String(cString: sqlite3_errmsg(destination))
            )
        }
    }

    // MARK: - REGEXP

    /// Exposes `REGEXP` to SQL (`text REGEXP pattern`), backed by
    /// case-insensitive NSRegularExpression with a small compiled cache.
    private func registerRegexpFunction() throws {
        let handle = try requireHandle()
        let result = sqlite3_create_function(
            handle,
            "regexp",
            2,
            SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            nil,
            { context, argc, argv in
                guard argc == 2, let argv,
                      let patternText = sqlite3_value_text(argv[0]) else {
                    sqlite3_result_int(context, 0)
                    return
                }
                guard let valueText = sqlite3_value_text(argv[1]) else {
                    sqlite3_result_int(context, 0)
                    return
                }
                let pattern = String(cString: patternText)
                guard let expression = RegexpCache.expression(for: pattern) else {
                    sqlite3_result_error(context, "invalid regular expression", -1)
                    return
                }
                let value = String(cString: valueText)
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                let matched = expression.firstMatch(in: value, options: [], range: range) != nil
                sqlite3_result_int(context, matched ? 1 : 0)
            },
            nil,
            nil
        )
        guard result == SQLITE_OK else {
            throw error(result)
        }
    }

    public var lastInsertRowID: Int64 {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return 0 }
        return sqlite3_last_insert_rowid(handle)
    }

    public func execute(_ sql: String) throws {
        try run(sql, [])
    }

    public func run(_ sql: String, _ bindings: [SQLValue]) throws {
        lock.lock()
        defer { lock.unlock() }
        let handle = try requireHandle()
        let statement = try prepare(sql, handle: handle)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_DONE:
                return
            case SQLITE_ROW:
                continue
            default:
                throw error(result)
            }
        }
    }

    public func query(_ sql: String, _ bindings: [SQLValue]) throws -> [[String: SQLValue]] {
        lock.lock()
        defer { lock.unlock() }
        let handle = try requireHandle()
        let statement = try prepare(sql, handle: handle)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)
        var rows: [[String: SQLValue]] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                rows.append(row(from: statement))
            case SQLITE_DONE:
                return rows
            default:
                throw error(result)
            }
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard let handle else { return }
        sqlite3_close(handle)
        self.handle = nil
    }

    // MARK: - Statements

    private func requireHandle() throws -> OpaquePointer {
        guard let handle else {
            throw DatabaseError(code: SQLITE_MISUSE, message: "Database is closed")
        }
        return handle
    }

    private func prepare(_ sql: String, handle: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw error(result)
        }
        return statement
    }

    private func bind(_ values: [SQLValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let value):
                result = sqlite3_bind_int64(statement, index, value)
            case .real(let value):
                result = sqlite3_bind_double(statement, index, value)
            case .text(let value):
                result = value.withCString {
                    sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
                }
            case .blob(let value):
                if value.isEmpty {
                    result = sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    result = value.withUnsafeBytes {
                        sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient)
                    }
                }
            }
            guard result == SQLITE_OK else {
                throw error(result)
            }
        }
    }

    private func row(from statement: OpaquePointer) -> [String: SQLValue] {
        var row: [String: SQLValue] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            guard let name = sqlite3_column_name(statement, index) else { continue }
            row[String(cString: name)] = value(from: statement, at: index)
        }
        return row
    }

    private func value(from statement: OpaquePointer, at index: Int32) -> SQLValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else { return .text("") }
            let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
            return .text(String(cString: cString))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    private func error(_ code: Int32) -> DatabaseError {
        let message: String
        if let handle, let text = sqlite3_errmsg(handle) {
            message = String(cString: text)
        } else {
            message = "SQLite error \(code)"
        }
        return DatabaseError(code: code, message: message)
    }
}

/// Process-wide cache of compiled REGEXP patterns. A picker query reuses one
/// pattern across every row, so a tiny cache removes per-row compilation.
private enum RegexpCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func expression(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] {
            return cached
        }
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        if cache.count >= 8 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[pattern] = expression
        return expression
    }
}
