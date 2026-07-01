import SwiftUI

@main
struct SwiftSpeedApp: App {
    @StateObject private var networkMonitor = NetworkMonitor()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(networkMonitor)
        } label: {
            Image(systemName: "speedometer")
        }
        .menuBarExtraStyle(.window)
    }
}
