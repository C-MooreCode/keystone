import Foundation

enum AppDeepLink {
    private static let scheme = "keystone"

    case tab(AppState.Tab)

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        guard let host = url.host else { return nil }

        switch host.lowercased() {
        case "tab":
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !path.isEmpty, let tab = AppState.Tab(deepLinkIdentifier: path) else { return nil }
            self = .tab(tab)
        default:
            return nil
        }
    }

    var url: URL {
        switch self {
        case let .tab(tab):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "tab"
            components.path = "/\(tab.deepLinkIdentifier)"
            return components.url ?? URL(string: "\(Self.scheme)://")!
        }
    }
}
