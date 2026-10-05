import Foundation

struct Deal: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let store: String
    let cat: String
    let size: String
    let was: Double
    let now: Double
    let emoji: String
    let url: URL?
    let imageURL: URL?

    var percentOff: Int { was > 0 ? Int(((1 - now / was) * 100).rounded()) : 0 }
    var saved: Double { was - now }
}

@MainActor
final class DealStore: ObservableObject {
    static let feedURL = URL(string: "https://smv-cmd.github.io/babydeals/deals.js")!
    private static let cacheKey = "cachedDealsJS"

    @Published var deals: [Deal] = []
    @Published var updated = ""
    @Published var isLoading = false
    @Published var error: String?

    init() {
        if let cached = UserDefaults.standard.string(forKey: Self.cacheKey) { _ = parse(cached) }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var req = URLRequest(url: Self.feedURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let text = String(data: data, encoding: .utf8), parse(text) else {
                error = "Couldn't read the deals feed."
                return
            }
            UserDefaults.standard.set(text, forKey: Self.cacheKey)
            error = nil
        } catch {
            self.error = deals.isEmpty ? "Offline and nothing saved yet." : "Offline. Showing saved deals."
        }
    }

    /// deals.js is `window.DEALS_DATA = {...};` — strip the wrapper and parse (JSON5 tolerates unquoted keys).
    private func parse(_ js: String) -> Bool {
        guard let eq = js.firstIndex(of: "="), let end = js.lastIndex(of: ";") else { return false }
        let body = String(js[js.index(after: eq)..<end])
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any],
              let raw = obj["deals"] as? [[String: Any]] else { return false }
        updated = obj["updated"] as? String ?? ""
        deals = raw.compactMap { d in
            guard let name = d["name"] as? String,
                  let now = (d["now"] as? NSNumber)?.doubleValue,
                  let was = (d["was"] as? NSNumber)?.doubleValue,
                  now < was else { return nil }
            return Deal(name: name, store: d["store"] as? String ?? "", cat: d["cat"] as? String ?? "",
                        size: d["size"] as? String ?? "Baby", was: was, now: now,
                        emoji: d["emoji"] as? String ?? "👶", url: (d["url"] as? String).flatMap(URL.init),
                        imageURL: (d["image"] as? String).flatMap(URL.init))
        }
        return true
    }
}
