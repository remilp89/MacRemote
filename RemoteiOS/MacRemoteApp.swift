import SwiftUI

@main
struct MacRemoteApp: App {
    @StateObject private var client = RemoteClient()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(client)
        }
    }
}
