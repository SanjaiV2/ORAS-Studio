import SwiftUI

struct ContentView: View {
    @EnvironmentObject var controller: ProjectController
    @State private var selectedSection: SidebarSection?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedSection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            DetailView(section: selectedSection)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    controller.openProject()
                } label: {
                    Label("Ouvrir un projet", systemImage: "folder.badge.plus")
                }
                .help("Ouvrir un dossier ORAS extrait (contenant 'romfs')")

                if controller.project != nil {
                    Divider()
                    Text(controller.project?.name ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Feuille de chargement
        .sheet(isPresented: $controller.isLoading) {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Chargement du projet…")
                    .font(.headline)
            }
            .padding(40)
            .frame(width: 280)
        }
        // Alerte d'erreur
        .alert(
            "Erreur lors du chargement",
            isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ProjectController())
        .frame(width: 1000, height: 650)
}
