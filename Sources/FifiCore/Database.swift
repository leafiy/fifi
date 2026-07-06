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

public final class Database {
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
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA busy_timeout=2000")
        } catch {
            close()
            throw error
        }
    }

    deinit {
        close()
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
