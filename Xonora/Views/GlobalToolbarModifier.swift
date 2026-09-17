import SwiftUI

struct GlobalToolbarModifier: ViewModifier {
    @EnvironmentObject var globalNav: GlobalNavigationViewModel
    var includeSettings: Bool = false
    var searchFilter: SearchFilter = .all

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        globalNav.openSearch(with: searchFilter)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.body)
                    }
                }

                if includeSettings {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            globalNav.showingSettings = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.body)
                        }
                    }
                }
            }
    }
}

extension View {
    func globalToolbar(includeSettings: Bool = false, searchFilter: SearchFilter = .all) -> some View {
        modifier(GlobalToolbarModifier(includeSettings: includeSettings, searchFilter: searchFilter))
    }
}
