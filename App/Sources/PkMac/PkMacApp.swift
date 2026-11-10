import SwiftUI
import AppKit

@main
struct PkMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    init() { ErrorReporter.install() }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { ErrorReporter.checkPreviousCrash() }
        if ProcessInfo.processInfo.environment["PKMAC_TOUR"] == "1" {
            // Diagnostic tour: visits every section once a save is open (used by the local test script).
            Task { @MainActor in
                while model?.save == nil { try? await Task.sleep(for: .milliseconds(300)) }
                for s in AppSection.allCases where s != .liveHex && s != .home {
                    Log.app("Tour: \(s.title)")
                    model?.section = s
                    try? await Task.sleep(for: .seconds(2.5))
                }
                model?.section = .boxes
                for t in InspectorTour.tabs {
                    Log.app("Tour scheda: \(t)")
                    NotificationCenter.default.post(name: .pkmacTourTab, object: t)
                    try? await Task.sleep(for: .seconds(2))
                }
                Log.app("Tour completato")
            }
        }
        if ProcessInfo.processInfo.environment["PKMAC_TEST_EXCEPTION"] == "1" {
            // Self-test of the error reporter: an AppKit exception must not close the app.
            Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
                NSException(name: .genericException, reason: "Eccezione di prova del sistema di segnalazione errori", userInfo: nil).raise()
            }
        }
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
        CommandGroup(after: .help) {
            Button("Mostra il registro degli errori") { ErrorReporter.revealLog() }
        }
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
            Divider()
            Button("Apri secondo salvataggio per trasferire…") { model.section = .transfer; model.openSecondPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model.save == nil)
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
