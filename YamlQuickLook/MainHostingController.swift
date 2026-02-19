import AppKit
import SwiftUI

/// Bridges the storyboard's NSHostingController slot to ContentView.
/// NSHostingController's generic rootView cannot be set directly from a storyboard,
/// so this subclass provides it at init time.
final class MainHostingController: NSHostingController<ContentView> {
    private var didSetInitialSize = false

    @objc required dynamic init?(coder: NSCoder) {
        super.init(coder: coder, rootView: ContentView())
        // Only enforce minimum size; don't let SwiftUI's ideal size override
        // the window after it's been created from the storyboard.
        sizingOptions = [.minSize]
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        guard !didSetInitialSize, let window = view.window else { return }
        didSetInitialSize = true
        window.setContentSize(NSSize(width: 720, height: 960))
        window.center()
    }
}
