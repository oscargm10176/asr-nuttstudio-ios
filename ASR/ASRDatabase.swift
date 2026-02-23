import Foundation
import SQLite3

final class ASRDatabase {
    private var db: OpaquePointer?

    deinit { close() }

    func open(dbPath: URL) throws {
        close()
        let rc = sqlite3_open(dbPath.path, &db)
        guard rc == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "ASR.DB", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "sqlite open failed: \(msg)"])
        }
        try initDB()
    }

    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    private func initDB() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS assets (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          tags TEXT NOT NULL,
          asset_rel_path TEXT NOT NULL,
          cover_rel_path TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
        """
        try exec(sql)
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        guard rc == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw NSError(domain: "ASR.DB", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    private func nowIso() -> String {
        let t = Int(Date().timeIntervalSince1970)
        return "\(t)"
    }

    func insertAsset(id: String, name: String, tags: String, assetRelPath: String, coverRelPath: String) throws {
        let sql = """
        INSERT INTO assets (id, name, tags, asset_rel_path, cover_rel_path, created_at)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError("prepare insert") }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, tags, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, assetRelPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, coverRelPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, nowIso(), -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step insert") }
    }

    func listAssets(root: URL) throws -> [AssetRow] {
        let sql = """
        SELECT id, name, tags, asset_rel_path, cover_rel_path
        FROM assets
        ORDER BY created_at DESC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError("prepare list") }
        defer { sqlite3_finalize(stmt) }

        var out: [AssetRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = colText(stmt, 0)
            let name = colText(stmt, 1)
            let tags = colText(stmt, 2)
            let assetRel = colText(stmt, 3)
            let coverRel = colText(stmt, 4)

            let assetAbs = root.appendingPathComponent(assetRel).path
            let coverAbs = root.appendingPathComponent(coverRel).path

            out.append(AssetRow(id: id, name: name, tags: tags, sourcePath: assetAbs, coverPath: coverAbs))
        }
        return out
    }

    func updateAsset(id: String, name: String, tags: String, newCoverRelPath: String?) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "ASR", code: 10, userInfo: [NSLocalizedDescriptionKey: "name no puede estar vacío"])
        }
        guard !tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "ASR", code: 11, userInfo: [NSLocalizedDescriptionKey: "tags no puede estar vacío"])
        }

        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try updateNameTags(id: id, name: name, tags: tags)
            if let rel = newCoverRelPath, !rel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try updateCover(id: id, coverRelPath: rel)
            }
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func updateNameTags(id: String, name: String, tags: String) throws {
        let sql = """
        UPDATE assets
        SET name = ?1, tags = ?2
        WHERE id = ?3;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError("prepare updateNameTags") }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, tags, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step updateNameTags") }
        if sqlite3_changes(db) == 0 {
            throw NSError(domain: "ASR", code: 12, userInfo: [NSLocalizedDescriptionKey: "No se encontró el asset (id) para actualizar"])
        }
    }

    private func updateCover(id: String, coverRelPath: String) throws {
        let sql = """
        UPDATE assets
        SET cover_rel_path = ?1
        WHERE id = ?2;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw dbError("prepare updateCover") }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, coverRelPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError("step updateCover") }
    }

    func deleteAsset(id: String) throws -> (assetRel: String?, coverRel: String?) {
        let sel = "SELECT asset_rel_path, cover_rel_path FROM assets WHERE id = ?1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sel, -1, &stmt, nil) == SQLITE_OK else { throw dbError("prepare select delete") }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        var assetRel: String?
        var coverRel: String?
        if sqlite3_step(stmt) == SQLITE_ROW {
            assetRel = colText(stmt, 0)
            coverRel = colText(stmt, 1)
        }

        let del = "DELETE FROM assets WHERE id = ?1;"
        var stmt2: OpaquePointer?
        guard sqlite3_prepare_v2(db, del, -1, &stmt2, nil) == SQLITE_OK else { throw dbError("prepare delete") }
        defer { sqlite3_finalize(stmt2) }

        sqlite3_bind_text(stmt2, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt2) == SQLITE_DONE else { throw dbError("step delete") }
        if sqlite3_changes(db) == 0 {
            throw NSError(domain: "ASR", code: 13, userInfo: [NSLocalizedDescriptionKey: "No se encontró el asset (id) para borrar"])
        }

        return (assetRel, coverRel)
    }

    private func colText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }

    private func dbError(_ prefix: String) -> Error {
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        return NSError(domain: "ASR.DB", code: -1, userInfo: [NSLocalizedDescriptionKey: "\(prefix): \(msg)"])
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
