import SwiftUI

struct LanguageView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var selectedLanguage: String = "system"

    private var sortedLocales: [String] {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted { a, b in
                let nameA = Locale(identifier: a).localizedString(forIdentifier: a) ?? a
                let nameB = Locale(identifier: b).localizedString(forIdentifier: b) ?? b
                return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
            }
    }

    var body: some View {
        List {
            Section {
                row(title: "System Default", subtitle: nil, tag: "system")
            } footer: {
                Text("Uses your device's language setting.")
            }

            Section {
                ForEach(sortedLocales, id: \.self) { code in
                    let nativeLocale = Locale(identifier: code)
                    let nativeName = nativeLocale.localizedString(forIdentifier: code)?.capitalized ?? code
                    let englishLocale = Locale(identifier: "en")
                    let englishName = englishLocale.localizedString(forIdentifier: code)?.capitalized

                    row(title: nativeName, subtitle: englishName, tag: code)
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedLanguage = preferences.appLanguage
        }
        .onChange(of: selectedLanguage) { _, newValue in
            preferences.appLanguage = newValue
        }
    }

    @ViewBuilder
    private func row(title: String, subtitle: String?, tag: String) -> some View {
        Button {
            selectedLanguage = tag
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, subtitle.lowercased() != title.lowercased() {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectedLanguage == tag {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LanguageView()
    }
}
