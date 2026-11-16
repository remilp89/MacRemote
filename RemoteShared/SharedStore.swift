import Foundation

/// Données partagées entre l'app iPhone et le widget (App Group).
enum SharedStore {
    /// Défini dans project.yml (APP_GROUP) et injecté dans Info.plist.
    static let suite = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    private static let key = "recentHosts"

    struct Entry: Codable, Identifiable, Equatable {
        var name: String
        var manual: Bool
        var lastUsed: Date
        var id: String { name }
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suite) }

    static func recent() -> [Entry] {
        guard let d = defaults?.data(forKey: key), let list = try? JSONDecoder().decode([Entry].self, from: d) else { return [] }
        return list
    }

    static func touch(name: String, manual: Bool) {
        var list = recent().filter { $0.name != name }
        list.insert(Entry(name: name, manual: manual, lastUsed: Date()), at: 0)
        if let d = try? JSONEncoder().encode(Array(list.prefix(5))) { defaults?.set(d, forKey: key) }
    }

    static func connectURL(_ e: Entry) -> URL {
        var c = URLComponents()
        c.scheme = "macremote"; c.host = "connect"
        c.queryItems = [URLQueryItem(name: "host", value: e.name), URLQueryItem(name: "manual", value: e.manual ? "1" : "0")]
        return c.url!
    }

    static func entry(from url: URL) -> Entry? {
        guard url.scheme == "macremote", url.host == "connect",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let name = items.first(where: { $0.name == "host" })?.value, !name.isEmpty else { return nil }
        return Entry(name: name, manual: items.first(where: { $0.name == "manual" })?.value == "1", lastUsed: Date())
    }
}
