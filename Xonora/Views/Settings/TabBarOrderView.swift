import SwiftUI

struct TabBarOrderView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var libraryViewModel = LibraryViewModel.shared
    @State private var tabs: [TabItem] = []
    @State private var enabledTabs: [Int: Bool] = [:]

    private let contentDependentTags: Set<Int> = [1, 3, 4] // Podcasts, Audiobooks, Radio

    private func hasContent(for tag: Int) -> Bool {
        switch tag {
        case 1: return !libraryViewModel.podcasts.isEmpty
        case 3: return !libraryViewModel.audiobooks.isEmpty
        case 4: return !libraryViewModel.radios.isEmpty
        default: return true
        }
    }

    private func contentLabel(for tag: Int) -> String {
        switch tag {
        case 1: return "podcasts"
        case 3: return "audiobooks"
        case 4: return "radio stations"
        default: return "content"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach(tabs) { tab in
                        HStack(spacing: 16) {
                            // Tab icon
                            Image(systemName: tab.icon)
                                .foregroundColor(.accentColor)
                                .frame(width: 24)

                            // Tab name + content status
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(tab.name))

                                if contentDependentTags.contains(tab.tag) {
                                    if !hasContent(for: tab.tag) {
                                        if preferences.isTabForceEnabled(tab.tag) {
                                            Text("No \(contentLabel(for: tab.tag)) available (shown anyway)")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        } else {
                                            Text("Hidden -- no \(contentLabel(for: tab.tag)) available")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }

                            Spacer()

                            // Toggle
                            if tab.isRequired {
                                Text("Required")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if contentDependentTags.contains(tab.tag) && !hasContent(for: tab.tag) {
                                // Force-enable toggle when no content
                                Toggle("", isOn: Binding(
                                    get: { preferences.isTabForceEnabled(tab.tag) },
                                    set: { newValue in
                                        preferences.setTabForceEnabled(tab.tag, enabled: newValue)
                                    }
                                ))
                                .labelsHidden()
                            } else {
                                Toggle("", isOn: Binding(
                                    get: { enabledTabs[tab.tag] ?? true },
                                    set: { newValue in
                                        let currentlyEnabled = enabledTabs.filter { $0.value }.count
                                        if !newValue && currentlyEnabled <= 2 {
                                            return
                                        }
                                        enabledTabs[tab.tag] = newValue
                                        preferences.setTabEnabled(tab.tag, enabled: newValue)
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveTab)
                } header: {
                    Text("Tabs")
                } footer: {
                    Text("Drag to reorder. Tabs with no available content are hidden automatically. Toggle on to always show. At least 2 tabs must be enabled.")
                }

                Section {
                    Button("Reset to Default") {
                        resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
            }

            // Live preview of tab bar
            VStack(spacing: 0) {
                // Hairline separator
                Rectangle()
                    .fill(Color(UIColor.separator))
                    .frame(height: 0.33)

                HStack(spacing: 0) {
                    ForEach(tabs.filter { enabledTabs[$0.tag] ?? true }) { tab in
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: .semibold))
                            Text(LocalizedStringKey(tab.name))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                        .foregroundColor(tab.tag == 2 ? .accentColor : .gray)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.bottom, 34)
                .background(.bar)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
        .navigationTitle("Tab Bar Order")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .toolbar {
            // EditButton removed as requested
        }
        .onAppear {
            loadTabs()
        }
    }

    private func loadTabs() {
        let order = preferences.tabBarOrder
        let allTabs = UserPreferences.allTabs

        // Sort by saved order
        tabs = order.compactMap { tag in
            allTabs.first { $0.tag == tag }
        }

        // Add any missing tabs
        for tab in allTabs where !tabs.contains(tab) {
            tabs.append(tab)
        }

        enabledTabs = preferences.tabsEnabled
    }

    private func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        preferences.tabBarOrder = tabs.map { $0.tag }
    }

    private func resetToDefaults() {
        preferences.tabBarOrder = UserPreferences.allTabs.map { $0.tag }
        for tab in UserPreferences.allTabs {
            preferences.setTabEnabled(tab.tag, enabled: true)
            preferences.setTabForceEnabled(tab.tag, enabled: false)
        }
        loadTabs()
    }
}

#Preview {
    NavigationStack {
        TabBarOrderView()
    }
}
