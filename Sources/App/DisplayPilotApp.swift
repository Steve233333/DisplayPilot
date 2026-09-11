import SwiftUI

@main
struct DisplayPilotApp: App {
    @State private var model: AppModel

    init() {
        // 启动即初始化：显示器监听、媒体键 tap、权限轮询都不该等到用户点开面板才跑。
        let model = AppModel()
        model.start()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
                .task {
                    model.start()
                    model.refreshPermissionNow()
                }
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
