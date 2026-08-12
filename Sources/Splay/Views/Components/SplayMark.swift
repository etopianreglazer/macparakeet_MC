import AppKit
import SwiftUI

/// The supplied three-splay mark for compact Splay surfaces. It keeps the
/// brand recognisable without turning the island into a logo treatment.
struct SplayMark: View {
    var size: CGSize = CGSize(width: 16, height: 18)

    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "splay-three-mark", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Splay")
    }
}
