import SwiftUI

enum SortMode: String, CaseIterable, Identifiable {
    case percent = "Biggest % off", saved = "Most $ saved", price = "Price: low to high"
    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var store = DealStore()
    @State private var search = ""
    @State private var retailer = "All retailers"
    @State private var maxPrice: Double = 0   // 0 = any
    @State private var sort: SortMode = .percent

    private var retailers: [String] { ["All retailers"] + Set(store.deals.map(\.store)).sorted() }

    private var filtered: [Deal] {
        store.deals
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .filter { retailer == "All retailers" || $0.store == retailer }
            .filter { maxPrice == 0 || $0.now < maxPrice }
            .sorted {
                switch sort {
                case .percent: return $0.percentOff > $1.percentOff
                case .saved: return $0.saved > $1.saved
                case .price: return $0.now < $1.now
                }
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                ForEach(filtered) { deal in
                    if let url = deal.url {
                        Link(destination: url) { DealRow(deal: deal) }
                    } else {
                        DealRow(deal: deal)
                    }
                }
                if filtered.isEmpty && !store.isLoading {
                    ContentUnavailableView("No deals match", systemImage: "tag.slash")
                }
                if !store.updated.isEmpty {
                    Text("Prices last scanned \(store.updated). Verify at the retailer before buying.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Baby Deals")
            .searchable(text: $search, prompt: "Onesie, sleeper…")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Retailer", selection: $retailer) { ForEach(retailers, id: \.self) { Text($0) } }
                        Picker("Max price", selection: $maxPrice) {
                            Text("Any price").tag(0.0)
                            ForEach([15.0, 30, 50, 100], id: \.self) { Text("Under $\(Int($0))").tag($0) }
                        }
                        Picker("Sort", selection: $sort) { ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) } }
                    } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                }
            }
            .overlay { if store.isLoading && store.deals.isEmpty { ProgressView() } }
        }
        .task { await store.refresh() }
    }
}

struct ProductImage: View {
    let deal: Deal
    var body: some View {
        Group {
            if let url = deal.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .empty: ProgressView()
                    default: Text(deal.emoji).font(.system(size: 34))
                    }
                }
            } else {
                Text(deal.emoji).font(.system(size: 34))
            }
        }
        .frame(width: 72, height: 72)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct DealRow: View {
    let deal: Deal
    var body: some View {
        HStack(spacing: 12) {
            ProductImage(deal: deal)
            VStack(alignment: .leading, spacing: 3) {
                Text(deal.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text("\(deal.store) · \(deal.cat) · \(deal.size)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(deal.now, format: .currency(code: "USD")).fontWeight(.bold).foregroundStyle(.green)
                    Text(deal.was, format: .currency(code: "USD")).strikethrough().foregroundStyle(.secondary).font(.subheadline)
                }
            }
            Spacer()
            Text("−\(deal.percentOff)%").font(.subheadline.bold()).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Color.orange, in: Capsule())
        }
        .padding(.vertical, 4)
    }
}
