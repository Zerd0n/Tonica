import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    // файлы могут прийти до того, как появилось окно
    static var pendingURLs: [URL] = []
    static var windowReady = false
    func application(_ application: NSApplication, open urls: [URL]) {
        if Self.windowReady {
            NotificationCenter.default.post(name: .tonicaOpenFiles, object: urls)
        } else {
            Self.pendingURLs += urls
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        ProcessRegistry.shared.terminateAll()
        TempFiles.cleanup()
    }
}

@main
struct TonicaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Tonica") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 640)
                .onAppear {
                    AppDelegate.windowReady = true
                    if !AppDelegate.pendingURLs.isEmpty {
                        model.add(urls: AppDelegate.pendingURLs)
                        AppDelegate.pendingURLs = []
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .tonicaOpenFiles)) { note in
                    if let urls = note.object as? [URL] { model.add(urls: urls) }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Добавить файлы…") { model.openFilesPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Button("Вставить обложку") { model.pasteCover(for: model.selectedTracks) }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(model.selection.isEmpty)
            }
        }
    }
}

extension Notification.Name {
    static let tonicaOpenFiles = Notification.Name("TonicaOpenFiles")
}
