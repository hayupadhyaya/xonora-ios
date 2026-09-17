import SwiftUI

struct CustomizeHomeView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var homeViewModel = HomeViewModel.shared
    @State private var sections: [SectionModel] = []
    @State private var enabledSections: [String: Bool] = [:]
    
    struct SectionModel: Identifiable, Equatable {
        let id: String
        let name: String
        let icon: String
        let isRequired: Bool
    }
    
    var body: some View {
        List {
            Section {
                ForEach(sections) { section in
                    HStack(spacing: 16) {
                    // Section icon
                    Image(systemName: section.icon)
                        .foregroundColor(.pink)
                        .frame(width: 24)
                    
                    // Section name
                    Text(LocalizedStringKey(section.name))
                    
                    Spacer()
                        
                        // Toggle (disabled for required sections)
                        if section.isRequired {
                            Text("Required")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { enabledSections[section.id] ?? true },
                                set: { newValue in
                                    enabledSections[section.id] = newValue
                                    preferences.setSectionEnabled(section.id, enabled: newValue)
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onMove(perform: moveSection)
            } header: {
                Text("Sections")
            } footer: {
                Text("Drag to reorder sections. Toggle to show or hide sections on the Home tab.")
            }
            
            Section {
                Button("Reset to Default") {
                    resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Customize Home")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .toolbar {
            // EditButton removed as requested
        }
        .onAppear {
            loadSections()
        }
        // Reload when dynamic sections change (e.g. finished loading)
        .onChange(of: homeViewModel.allSections) { _, _ in
            loadSections()
        }
    }
    
    private func loadSections() {
        // 1. Get all available static sections
        let staticSections = UserPreferences.allHomeSections.map {
            SectionModel(id: $0.id, name: $0.name, icon: $0.icon, isRequired: $0.isRequired)
        }
        
        // 2. Get all dynamic sections from HomeViewModel
        let dynamicSections = homeViewModel.allSections.map {
            SectionModel(
                id: $0.id,
                name: $0.name,
                icon: $0.icon,
                isRequired: false
            )
        }
        
        // 3. Combine them
        let allAvailable = staticSections + dynamicSections
        
        // 4. Load saved order
        let order = preferences.homeSectionOrder
        
        // 5. Sort based on saved order
        var orderedSections: [SectionModel] = []
        
        // First add existent sections in their saved order
        for id in order {
            if let section = allAvailable.first(where: { $0.id == id }) {
                orderedSections.append(section)
            }
        }
        
        // Then append any new sections (dynamic or static) that aren't in the saved order yet
        for section in allAvailable where !orderedSections.contains(section) {
            orderedSections.append(section)
        }
        
        self.sections = orderedSections
        self.enabledSections = preferences.homeSectionsEnabled
    }
    
    private func moveSection(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        preferences.homeSectionOrder = sections.map { $0.id }
    }
    
    private func resetToDefaults() {
        // Reset to default order: Static sections first, then dynamic
        let staticDefaults = UserPreferences.allHomeSections.map { $0.id }
        let dynamicDefaults = homeViewModel.allSections.map { $0.id }
        
        preferences.homeSectionOrder = staticDefaults + dynamicDefaults
        
        // Enable all
        for id in preferences.homeSectionOrder {
            preferences.setSectionEnabled(id, enabled: true)
        }
        loadSections()
    }
}

#Preview {
    NavigationStack {
        CustomizeHomeView()
    }
}
