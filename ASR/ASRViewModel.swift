import Foundation
import SwiftUI
import Combine  

@MainActor
final class ASRViewModel: ObservableObject {
    @Published var rootURL: URL?
    @Published var assets: [AssetRow] = []

    @Published var fileURL: URL?
    @Published var name: String = ""
    @Published var tags: String = ""

    @Published var selected: AssetRow?
    @Published var isEditing: Bool = false

    @Published var fileTypeFilter: FileTypeFilter = .all
    @Published var q: String = ""
    @Published var viewMode: ViewMode = .grid

    @Published var coverURL: URL?
    @Published var isPickingCover: Bool = false
    @Published var coverRelPath: String = ""

    @Published var showAlert: Bool = false
    @Published var alertMessage: String = ""

    private let bookmarks = BookmarkStore()
    private let files = ASRFileService()
    private let db = ASRDatabase()

    var filteredAssets: [AssetRow] {
        let term = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return assets.filter { a in
            let hay = "\(a.name) \(a.tags)".lowercased()
            let matchesSearch = term.isEmpty || hay.contains(term)

            let type = getFileType(a.sourcePath)
            let matchesType = (fileTypeFilter == .all) || (type == fileTypeFilter.normalized)

            return matchesSearch && matchesType
        }
    }

    func boot() async {
        guard let url = bookmarks.loadBookmarkedURL() else { return }
        if url.startAccessingSecurityScopedResource() {
            self.rootURL = url
            do {
                try openDBIfPossible()
                try await refresh()
            } catch { }
        }
    }

    func setRootFolder(_ url: URL) {
        rootURL?.stopAccessingSecurityScopedResource()

        do { try bookmarks.saveBookmark(for: url) }
        catch { return alert("No pude guardar permisos del folder.") }

        _ = url.startAccessingSecurityScopedResource()
        rootURL = url
        resetFormAll()

        Task {
            do {
                try openDBIfPossible()
                try await refresh()
            } catch {
                alert("No pude abrir el library. \(error.localizedDescription)")
            }
        }
    }

    func setFile(_ picked: URL) { fileURL = picked }

    func importCover(from picked: URL) {
        guard let root = rootURL else { return }
        isPickingCover = true
        coverURL = nil
        coverRelPath = ""

        Task {
            let didAccess = picked.startAccessingSecurityScopedResource()
            defer { if didAccess { picked.stopAccessingSecurityScopedResource() } }

            do {
                let imported = try files.importCover(root: root, source: picked)
                coverURL = URL(fileURLWithPath: imported.coverAbsPath)
                coverRelPath = imported.coverRelPath
            } catch {
                alert("No pude leer/importar la imagen. \(error.localizedDescription)")
            }
            isPickingCover = false
        }
    }

    func refresh() async throws {
        guard let root = rootURL else {
            assets = []
            return
        }
        try openDBIfPossible()
        assets = try db.listAssets(root: root)
    }

    func startEdit(_ a: AssetRow) {
        selected = a
        isEditing = true

        fileURL = URL(fileURLWithPath: a.sourcePath)
        name = a.name
        tags = a.tags

        coverURL = URL(fileURLWithPath: a.coverPath)
        coverRelPath = ""
    }

    func cancelEdit() {
        selected = nil
        isEditing = false
        fileURL = nil
        name = ""
        tags = ""
        coverURL = nil
        coverRelPath = ""
    }

    func save() async {
        guard let root = rootURL else { return alert("Selecciona la carpeta de Library primero.") }
        guard let file = fileURL else { return alert("Selecciona un archivo.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return alert("Ponle nombre.") }
        guard !tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return alert("Pon tags.") }
        guard !isPickingCover else { return alert("Espera, estoy importando la imagen...") }
        guard !coverRelPath.isEmpty else { return alert("Sube una imagen.") }

        do {
            try openDBIfPossible()

            let didAccess = file.startAccessingSecurityScopedResource()
            defer { if didAccess { file.stopAccessingSecurityScopedResource() } }

            let copied = try files.copyAsset(root: root, source: file)
            try db.insertAsset(
                id: copied.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags.trimmingCharacters(in: .whitespacesAndNewlines),
                assetRelPath: copied.assetRelPath,
                coverRelPath: coverRelPath
            )

            resetFormAfterSave()
            try await refresh()
        } catch {
            alert("No pude guardar. \(error.localizedDescription)")
        }
    }

    func update() async {
        guard rootURL != nil else { return alert("Selecciona la carpeta de Library primero.") }
        guard let sel = selected else { return alert("Selecciona un asset para editar.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return alert("Ponle nombre.") }
        guard !tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return alert("Pon tags.") }
        guard !isPickingCover else { return alert("Espera, estoy importando la imagen...") }

        do {
            try openDBIfPossible()
            let newCover: String? = coverRelPath.isEmpty ? nil : coverRelPath

            try db.updateAsset(
                id: sel.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: tags.trimmingCharacters(in: .whitespacesAndNewlines),
                newCoverRelPath: newCover
            )

            cancelEdit()
            try await refresh()
        } catch {
            alert("No pude actualizar. \(error.localizedDescription)")
        }
    }

    func deleteSelected() async {
        guard let root = rootURL else { return }
        guard let sel = selected else { return }

        do {
            try openDBIfPossible()
            let rels = try db.deleteAsset(id: sel.id)

            if let assetRel = rels.assetRel {
                files.removeIfExists(root.appendingPathComponent(assetRel))
            }
            if let coverRel = rels.coverRel {
                files.removeIfExists(root.appendingPathComponent(coverRel))
            }

            cancelEdit()
            try await refresh()
        } catch {
            alert("No pude borrar. \(error.localizedDescription)")
        }
    }

    private func openDBIfPossible() throws {
        guard let root = rootURL else { return }
        let dirs = try files.ensureDirs(root: root)
        try db.open(dbPath: dirs.dbPath)
    }

    private func resetFormAll() {
        cancelEdit()
        fileTypeFilter = .all
        q = ""
        viewMode = .grid
    }

    private func resetFormAfterSave() {
        fileURL = nil
        name = ""
        tags = ""
        coverURL = nil
        coverRelPath = ""
    }

    func alert(_ msg: String) {
        alertMessage = msg
        showAlert = true
    }
}
