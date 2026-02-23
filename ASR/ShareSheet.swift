import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable, Identifiable {
    let id = UUID()
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
