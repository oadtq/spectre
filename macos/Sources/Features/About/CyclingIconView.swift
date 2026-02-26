import SwiftUI
import GhosttyKit

/// A view that cycles through Ghostty's official icon variants.
struct CyclingIconView: View {
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage!)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}
