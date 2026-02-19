import Foundation

final class PreviewSettings: ObservableObject {
    static let shared = PreviewSettings()

    private enum Key {
        static let fontSize    = "previewFontSize"
        static let lineNumbers = "previewLineNumbers"
        static let wordWrap    = "previewWordWrap"
    }

    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Key.fontSize) }
    }

    @Published var showLineNumbers: Bool {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: Key.lineNumbers) }
    }

    @Published var wordWrap: Bool {
        didSet { UserDefaults.standard.set(wordWrap, forKey: Key.wordWrap) }
    }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Key.fontSize)
        fontSize        = stored > 0 ? stored : 13
        showLineNumbers = UserDefaults.standard.object(forKey: Key.lineNumbers) as? Bool ?? true
        wordWrap        = UserDefaults.standard.bool(forKey: Key.wordWrap)
    }
}
