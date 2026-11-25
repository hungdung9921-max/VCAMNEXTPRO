import SwiftUI

@main
struct VCAMNEXTPROApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
