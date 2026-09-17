import SwiftUI

struct AppearanceView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var selectedScheme: String = "auto"
    @State private var selectedAccentColor: Color = .accentColor
    
    // Preset accent colors
    private let accentColors: [Color] = [
        .pink,
        .red,
        .orange,
        .yellow,
        .green,
        .mint,
        .teal,
        .cyan,
        .blue,
        .indigo,
        .purple,
        Color(red: 0.6, green: 0.4, blue: 0.8) // Lavender
    ]
    
    private let columns = [
        GridItem(.adaptive(minimum: 50))
    ]
    
    var body: some View {
        List {
            // Color Scheme Section
            Section {
                Picker("Theme", selection: $selectedScheme) {
                    Label("Auto", systemImage: "circle.lefthalf.filled")
                        .tag("auto")
                    Label("Light", systemImage: "sun.max.fill")
                        .tag("light")
                    Label("Dark", systemImage: "moon.fill")
                        .tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Theme")
            } footer: {
                Text("Auto follows your device settings.")
            }
            
            // Accent Color Section
            Section {
                LazyVGrid(columns: columns, spacing: 16) {
                    // Default (system) option
                    Button {
                        preferences.accentColorHex = ""
                        selectedAccentColor = .accentColor
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.pink, .purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                            
                            if preferences.accentColorHex.isEmpty {
                                Image(systemName: "checkmark")
                                    .font(.headline.bold())
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Preset colors
                    ForEach(accentColors, id: \.self) { color in
                        Button {
                            selectedAccentColor = color
                            preferences.accentColorHex = color.toHex() ?? ""
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 44, height: 44)
                                
                                if let hex = color.toHex(), preferences.accentColorHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.headline.bold())
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Choose a color for buttons and highlights throughout the app.")
            }
            
            // Preview Section
            Section("Preview") {
                HStack(spacing: 16) {
                    Button("Button") {}
                        .buttonStyle(.borderedProminent)
                    
                    Toggle("Toggle", isOn: .constant(true))
                        .labelsHidden()
                    
                    Slider(value: .constant(0.5))
                        .frame(width: 80)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedScheme = preferences.colorSchemePreference
            if let color = preferences.accentColor {
                selectedAccentColor = color
            }
        }
        .onChange(of: selectedScheme) { _, newValue in
            preferences.colorSchemePreference = newValue
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
    }
}
