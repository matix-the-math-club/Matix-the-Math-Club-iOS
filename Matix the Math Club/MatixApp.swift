import SwiftUI

@main
struct MatixApp: App {
    var body: some Scene {
        WindowGroup {
            RootShell()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}

struct RootShell: View {
    var body: some View {
        #if os(macOS)
        WebShellView()
            .frame(minWidth: 1080, minHeight: 700)
        #else
        WebShellView()
        #endif
    }
}
