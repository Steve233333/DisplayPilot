import SwiftUI

@main
struct DisplayPilotApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .task { model.start() }
        } label: {
            Image("device-desktop")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
