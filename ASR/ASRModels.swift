import Foundation
import UniformTypeIdentifiers

struct AssetRow: Identifiable, Hashable {
    var id: String
    var name: String
    var tags: String
    var sourcePath: String   // ABSOLUTO dentro del Library
    var coverPath: String    // ABSOLUTO dentro del Library
}

enum ViewMode: String { case grid, list }

enum FileTypeFilter: String, CaseIterable, Identifiable {
    case all
    case _3d
    case image
    case video
    case audio
    case document

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case ._3d: return "3D (FBX, OBJ)"
        case .image: return "Images"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Documents"
        }
    }

    var normalized: String {
        switch self {
        case ._3d: return "3d"
        default: return rawValue
        }
    }
}

func getFileType(_ path: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    if ext.isEmpty { return "other" }

    if ["fbx","obj","glb","gltf","blend"].contains(ext) { return "3d" }
    if ["png","jpg","jpeg","webp","tga"].contains(ext) { return "image" }
    if ["mp4","mov","avi","webm"].contains(ext) { return "video" }
    if ["wav","mp3","ogg"].contains(ext) { return "audio" }
    if ["pdf","doc","docx"].contains(ext) { return "document" }

    return ext
}

func getFileExtLabel(_ path: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension
    return (ext.isEmpty ? "file" : ext).uppercased()
}

extension UTType {
    static let webP = UTType(filenameExtension: "webp") ?? .image
}
