import SwiftUI

@main
struct SmartHomeApp: App {
    @State private var home: Home
    @State private var agent: HomeAgent

    init() {
        let home = Home()
        _home = State(initialValue: home)
        _agent = State(initialValue: HomeAgent(home: home))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(home)
                .environment(agent)
                .preferredColorScheme(.dark)
        }
    }
}
