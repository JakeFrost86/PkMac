import SwiftUI
import AppKit

@main
struct PkMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("PkMac", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    delegate.model = model
                    await model.bootstrap()
                    if let pending = delegate.pendingOpen.first {
                        delegate.pendingOpen.removeAll()
                        await model.open(pending)
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1380, height: 860)
        .commands { PkMacCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel?
    @MainActor var pendingOpen: [URL] = []

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppIconManager.current != AppIconManager.defaultID {
            AppIconManager.apply(AppIconManager.current, persist: false)
        }
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let model, model.engineState == .ready {
            Task { await model.open(url) }
        } else {
            pendingOpen = [url]
        }
    }

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.save?.dirty == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Hai modifiche non salvate"
        alert.informativeText = "Se esci ora andranno perse."
        alert.addButton(withTitle: "Salva ed esci")
        alert.addButton(withTitle: "Esci senza salvare")
        alert.addButton(withTitle: "Annulla")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                await model.saveFile()
                NSApp.reply(toApplicationShouldTerminate: model.save?.dirty != true)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct PkMacCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Apri salvataggio…") { model.openPanel() }
                .keyboardShortcut("o")
            Menu("Recenti") {
                ForEach(model.recentFiles, id: \.self) { path in
                    Button(URL(fileURLWithPath: path).lastPathComponent) {
                        Task { await model.open(URL(fileURLWithPath: path)) }
                    }
                }
            }
            .disabled(model.recentFiles.isEmpty)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Salva con verifica checksum") { Task { await model.saveFile() } }
                .keyboardShortcut("s")
                .disabled(model.save == nil)
            Button("Esporta come…") { model.saveAsPanel() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.save == nil)
            Divider()
            Button("Chiudi salvataggio") { model.closeSave() }
                .disabled(model.save == nil)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(model.save?.undo.map { "Annulla \($0)" } ?? "Annulla") { Task { await model.undo() } }
                .keyboardShortcut("z")
                .disabled(model.save?.undo == nil)
            Button(model.save?.redo.map { "Ripeti \($0)" } ?? "Ripeti") { Task { await model.redo() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(model.save?.redo == nil)
        }
        CommandMenu("Box") {
            Group {
            Button("Box precedente") { Task { await model.showBox(model.currentBox - 1) } }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            Button("Box successivo") { Task { await model.showBox(model.currentBox + 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
            Divider()
            Button("Importa set Showdown…") { model.showShowdownImport = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Crea Pokémon legale…") { model.showCreate = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Legalizza box") { Task { await model.legalizeBox() } }
            Button("Esporta box…") { model.exportBox() }
            }
            .disabled(model.save == nil)
        }
    }
}
