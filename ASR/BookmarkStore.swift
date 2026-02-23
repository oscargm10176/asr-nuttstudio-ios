import Foundation

final class BookmarkStore {
    private let key = "asr.rootDir.url"

    func saveBookmark(for url: URL) {
        UserDefaults.standard.set(url.path, forKey: key)
    }

    func loadBookmarkedURL() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
