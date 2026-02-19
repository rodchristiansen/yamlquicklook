import Foundation

enum ContentTab: Hashable {
    case status, preview, settings
}

final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var selectedTab: ContentTab = .status
    @Published var openedURL: URL? = nil
    private init() {}
}
