import SwiftUI

/// Settings sheet to pick the TV provider/county lineup that supplies channel numbers. The
/// choice is set-once and persisted (``ChannelLineupStore``); picking one swaps the numbers
/// used by tuning, the EPG list, and Siri. "Built-in default" reverts to the compiled table.
@MainActor
struct LineupPickerView: View {
    @Bindable var store: ChannelLineupStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(
                        title: "Built-in default",
                        subtitle: "\(KnownChannelNumbers.defaultMapping.count) channels",
                        isSelected: store.selectedLineupID == nil
                    ) { store.selectedLineupID = nil }
                } footer: {
                    Text("Channel numbers vary by TV provider and region. Pick yours so tuning, the guide, and Siri use the right numbers.")
                }

                if store.isLoading && store.catalog == nil {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading lineups…").foregroundStyle(.secondary)
                        }
                    }
                } else if let error = store.lastError, store.catalog == nil {
                    Section {
                        Text("Couldn't load lineups: \(error)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if !filtered.isEmpty {
                    Section("Digi by county") {
                        ForEach(filtered) { lineup in
                            row(
                                title: lineup.region,
                                subtitle: "\(lineup.numbers.count) channels",
                                isSelected: store.selectedLineupID == lineup.id
                            ) { store.selectedLineupID = lineup.id }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "County")
            .navigationTitle("Channel lineup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { if store.catalog == nil { await store.load() } }
        }
    }

    private var filtered: [ChannelLineup] {
        let all = store.lineups
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.region.localizedCaseInsensitiveContains(search)
                || $0.provider.localizedCaseInsensitiveContains(search)
        }
    }

    @ViewBuilder
    private func row(
        title: String, subtitle: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
    }
}
