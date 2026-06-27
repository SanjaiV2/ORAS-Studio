import SwiftUI

@main
struct ORASStudioApp: App {
    @StateObject private var controller = ProjectController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // Remplace "Nouveau" par "Ouvrir un projet"
            CommandGroup(replacing: .newItem) {
                Button("Ouvrir un projet ORAS…") {
                    controller.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
