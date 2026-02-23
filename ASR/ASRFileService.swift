import Foundation

final class ASRFileService {
    struct Dirs {
        let dbDir: URL
        let assetsDir: URL
        let coversDir: URL
        let dbPath: URL
    }

    func ensureDirs(root: URL) throws -> Dirs {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else {
            throw NSError(domain: "ASR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Root dir no existe"])
        }

        let dbDir = root.appendingPathComponent("asr-db", isDirectory: true)
        let assetsDir = root.appendingPathComponent("assets", isDirectory: true)
        let coversDir = root.appendingPathComponent("covers", isDirectory: true)
        let dbPath = dbDir.appendingPathComponent("assetroom.sqlite", isDirectory: false)

        try fm.createDirectory(at: dbDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: coversDir, withIntermediateDirectories: true)

        return Dirs(dbDir: dbDir, assetsDir: assetsDir, coversDir: coversDir, dbPath: dbPath)
    }

    func copyAsset(root: URL, source: URL) throws -> (id: String, assetRelPath: String, assetAbsPath: String) {
        let dirs = try ensureDirs(root: root)

        let ext = source.pathExtension.lowercased()
        let id = UUID().uuidString
        let fileName = ext.isEmpty ? "asset_\(id)" : "asset_\(id).\(ext)"
        let dst = dirs.assetsDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: source, to: dst)

        let rel = "assets/\(fileName)"
        return (id: id, assetRelPath: rel, assetAbsPath: dst.path)
    }

    struct ImportedCover {
        let coverRelPath: String
        let coverAbsPath: String
        let coverExt: String
    }

    func importCover(root: URL, source: URL) throws -> ImportedCover {
        let dirs = try ensureDirs(root: root)

        let ext = source.pathExtension.lowercased()
        let extNorm: String
        switch ext {
        case "png": extNorm = "png"
        case "webp": extNorm = "webp"
        case "jpg", "jpeg": extNorm = "jpg"
        default: extNorm = "jpg"
        }

        let fileName = "cover_\(UUID().uuidString).\(extNorm)"
        let dst = dirs.coversDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: dst.path) {
            try FileManager.default.removeItem(at: dst)
        }
        try FileManager.default.copyItem(at: source, to: dst)

        let rel = "covers/\(fileName)"
        return ImportedCover(coverRelPath: rel, coverAbsPath: dst.path, coverExt: extNorm)
    }

    func removeIfExists(_ url: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }
}
