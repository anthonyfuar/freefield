import AppKit
import FreefieldCore
import SwiftUI
import UserNotifications

@main
struct FreefieldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app: AppModel

    init() {
        _ = AppLanguage.atLaunch
        let model = AppModel()
        _app = State(initialValue: model)
        AIChecks.app = model
        let library = model.library
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { library.flush() }
        }
    }

    var body: some Scene {
        Window("Freefield", id: "main") {
            ContentView()
                .environment(app)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1360, height: 860)
        .windowToolbarStyle(.unified)
        .commands { FreefieldCommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        Appearance.apply(UserDefaults.standard.string(forKey: SettingsKey.appearance))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}

struct FreefieldCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("New Image")) { app.selection = .tool(.create) }
                .keyboardShortcut("n")
            Button(L("New Video")) { app.openVideo("createVideo") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(L("Import Images…")) {
                for data in ImageIntake.pick(multiple: true) {
                    app.library.importImage(data: data, name: E("Imported") + ".png")
                }
                app.selection = .library
            }
            .keyboardShortcut("o")
            Button(L("Import Videos…")) { LibraryImport.run(app, videosOnly: true) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandMenu(L("Tools")) {
            Button(L("Create Image")) { app.selection = .tool(.create) }.keyboardShortcut("1")
            Button(Tool.edit.title) { app.selection = .tool(.edit) }.keyboardShortcut("2")
            Button(Tool.inpaint.title) { app.selection = .tool(.inpaint) }.keyboardShortcut("3")
            Button(Tool.relight.title) { app.selection = .tool(.relight) }.keyboardShortcut("4")
            Button(Tool.upscale.title) { app.selection = .tool(.upscale) }.keyboardShortcut("5")
            Button(L("Styles")) { app.selection = .styles }.keyboardShortcut("6")
            Button(L("Characters")) { app.selection = .characters }.keyboardShortcut("7")
            Button(L("Photo Effects")) { app.selection = .apps }.keyboardShortcut("8")
            Button(L("Library")) { app.selection = .library }.keyboardShortcut("9")
            Divider()
            Menu(L("All Tools")) {
                ForEach([Tool.storyboard, .photoSession] + Tool.editingTools) { tool in
                    Button(tool.title) { app.selection = .tool(tool) }
                }
            }
            Menu(L("Video Tools")) {
                ForEach(VideoCatalog.all) { tool in
                    Button(tool.name) { app.openVideo(tool.id) }
                }
            }
            Divider()
            Button(L("Refresh Models and Balance")) { Task { await app.refreshModels() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Link(L("Get an OpenRouter API Key"), destination: Provider.openRouter.keyURL)
            Link(L("Get a Google AI Studio API Key"), destination: Provider.google.keyURL)
            Divider()
            Button(L("Show Welcome Screen")) { app.showOnboarding = true }
        }
    }
}
