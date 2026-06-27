import SwiftUI
import UniformTypeIdentifiers

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

                if let name = controller.project?.name {
                    Divider()
                    projectStatusChip(name: name)
                }
            }
        }
        // MARK: — Sélecteur de dossier sécurisé (sandbox-safe)
        .fileImporter(
            isPresented: $controller.showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            controller.handlePickerResult(result)
        }
        // MARK: — Feuille de chargement
        .sheet(isPresented: $controller.isLoading) {
            LoadingSheet()
        }
        // MARK: — Alerte erreur
        .alert(
            "Erreur",
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

    // MARK: — Chip d'état projet

    @ViewBuilder
    private func projectStatusChip(name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.small)
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: — Feuille de chargement

private struct LoadingSheet: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.2)
            Text("Chargement du projet…").font(.headline)
            Text("Validation et lecture des archives GARC.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(width: 300)
    }
}

#Preview {
    ContentView()
        .environmentObject(ProjectController())
        .frame(width: 1000, height: 650)
}
