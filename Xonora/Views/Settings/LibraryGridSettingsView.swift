import SwiftUI

struct LibraryGridSettingsView: View {
    @ObservedObject private var prefs = UserPreferences.shared

    private let isIPad = UIDevice.current.userInterfaceIdiom == .pad

    private var portraitDefault: Int { isIPad ? 4 : 2 }
    private var portraitRange: ClosedRange<Int> { isIPad ? 4...8 : 2...4 }

    private var landscapeDefault: Int { isIPad ? 8 : 4 }
    private var landscapeRange: ClosedRange<Int> { isIPad ? 8...16 : 4...8 }

    private let categories: [(name: String, key: String)] = [
        ("Albums", "albums"),
        ("Playlists", "playlists"),
        ("Audiobooks", "audiobooks"),
        ("Podcasts", "podcasts"),
        ("Radio", "radios"),
    ]

    var body: some View {
        List {
            Section("Portrait") {
                ForEach(categories, id: \.key) { category in
                    columnRow(category: category, landscape: false,
                              default: portraitDefault, range: portraitRange)
                }
            }

            Section("Landscape") {
                ForEach(categories, id: \.key) { category in
                    columnRow(category: category, landscape: true,
                              default: landscapeDefault, range: landscapeRange)
                }
            }

            Section {
                Button("Reset All to Default") {
                    for category in categories {
                        prefs.setGridColumnCount(0, for: category.key, landscape: false)
                        prefs.setGridColumnCount(0, for: category.key, landscape: true)
                    }
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Grid Columns")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func columnRow(category: (name: String, key: String),
                           landscape: Bool,
                           default defaultCount: Int,
                           range: ClosedRange<Int>) -> some View {
        let pref = prefs.gridColumnCount(for: category.key, landscape: landscape)
        let count = pref > 0 ? pref : defaultCount

        HStack {
            Text(category.name)
            Spacer()
            Text("\(count)")
                .font(.body.monospacedDigit())
                .foregroundColor(pref > 0 ? .primary : .secondary)
                .frame(minWidth: 28, alignment: .trailing)
            Stepper("", value: Binding(
                get: { count },
                set: { new in
                    prefs.setGridColumnCount(new == defaultCount ? 0 : new,
                                            for: category.key, landscape: landscape)
                }
            ), in: range)
            .labelsHidden()
            .fixedSize()
        }
    }
}
