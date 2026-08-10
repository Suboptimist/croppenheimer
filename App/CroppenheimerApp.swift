import SwiftUI
import WidgetKit

@main
struct CroppenheimerApp: App {
    init() {
        // Widget timelines use .never, so nudge WidgetKit to re-render
        // whenever the app launches (e.g. after an update changes the design).
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some Scene {
        // A single Window, not a WindowGroup: one crop session at a time, and
        // incoming open requests reuse this window instead of spawning blank ones.
        Window("Croppenheimer", id: "croppenheimer") {
            WebView()
                .frame(minWidth: 900, minHeight: 640)
                .onOpenURL { url in
                    // Photos opened with "Open With" or dropped on the Dock
                    // icon; the widget's croppenheimer:// URL just activates.
                    if url.isFileURL {
                        PhotoBridge.shared.open(url)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .defaultSize(width: 1220, height: 820)
    }
}
