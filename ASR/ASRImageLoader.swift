import Foundation
import UIKit

enum ASRImageLoader {
    static func uiImage(fromFilePath path: String) -> UIImage? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}
