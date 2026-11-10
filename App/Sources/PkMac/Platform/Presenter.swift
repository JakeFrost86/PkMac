import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Dialogs, file pickers and exports with one API for both platforms.
// macOS keeps the classic modal NSAlert / NSOpenPanel; on iPhone / iPad the model publishes a request
// that RootView presents (.alert, .fileImporter, document exporter) and the async call resumes when the
// user answers.

/// Calls `resume` at most once, whatever path closes the dialog.
final class Once<T>: @unchecked Sendable {
    private var fn: ((T) -> Void)?
    init(_ fn: @escaping (T) -> Void) { self.fn = fn }
    func callAsFunction(_ value: T) { let f = fn; fn = nil; f?(value) }
}

struct DialogRequest: Identifiable {
    let id = UUID()
    var title: String
    var message: String?
    /// The last button is the cancel button.
    var buttons: [String]
    var resume: Once<Int>
}

struct FilePickRequest: Identifiable {
    let id = UUID()
    var folder: Bool
    var types: [UTType]
    var resume: Once<URL?>
}

struct ExportRequest: Identifiable {
    let id = UUID()
    var urls: [URL]
}

extension AppModel {
    /// Shows a question; returns the index of the pressed button (the last one is "cancel").
    func ask(_ title: String, _ message: String? = nil, buttons: [String]) async -> Int {
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        for b in buttons { alert.addButton(withTitle: b) }
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        #else
        return await withCheckedContinuation { cont in
            dialog = DialogRequest(title: title, message: message, buttons: buttons, resume: Once { cont.resume(returning: $0) })
        }
        #endif
    }

    /// Picks one file to read.
    func pickFile(message: String, prompt: String = L("Apri"), types: [UTType] = [.item]) async -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
        #else
        return await withCheckedContinuation { cont in
            filePick = FilePickRequest(folder: false, types: types, resume: Once { cont.resume(returning: $0) })
            showFilePicker = true
        }
        #endif
    }

    /// Where to write exported files. macOS asks for a folder; iOS writes into a fresh temporary
    /// folder and `finishExport` then offers the files to the system (Files, AirDrop, …).
    func exportFolder(prompt: String) async -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
        #else
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #endif
    }

    /// After an export: shows the files in Finder (or opens the folder); on iOS presents the exporter.
    func finishExport(_ urls: [URL], folder: URL? = nil) {
        #if os(macOS)
        if let folder { NSWorkspace.shared.open(folder) } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        #else
        var files = urls
        if let folder, files.isEmpty {
            files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        }
        if !files.isEmpty { exportRequest = ExportRequest(urls: files) }
        #endif
    }

    /// "Show in Finder": on iOS the file is offered for export instead.
    func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        exportRequest = ExportRequest(urls: [url])
        #endif
    }

    /// Opens a folder in Finder; on iOS opens the Files app when the folder is visible there.
    func openFolder(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let target = url.standardizedFileURL.path.hasPrefix(docs.standardizedFileURL.path) ? url : docs
        if let files = URL(string: "shareddocuments://" + target.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) {
            UIApplication.shared.open(files)
        }
        #endif
    }
}

// MARK: - Files outside the app (iOS)

/// On iOS a save picked in Files may live in another app's container or in iCloud Drive, where PkMac can
/// touch only that file (not its folder, so no atomic replace and no backups next to it). The engine works
/// on a copy inside the sandbox; after every successful save the copy is written back to the original
/// with NSFileCoordinator. Bookmarks keep "recent files" reopenable after a relaunch.
/// On macOS everything is opened in place and these calls do nothing.
@MainActor enum FileBridge {
    #if os(iOS)
    private static var originals: [String: URL] = [:]     // working path → original URL
    private static var bookmarks: [String: Data] {
        get { (UserDefaults.standard.dictionary(forKey: "fileBookmarks") as? [String: Data]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "fileBookmarks") }
    }

    static func isInsideSandbox(_ url: URL) -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        let p = url.resolvingSymlinksInPath().path
        return p.hasPrefix(home + "/") || p.hasPrefix("/private" + home + "/")
    }
    #endif

    /// The file the engine should open for `url`.
    static func prepare(_ url: URL) throws -> URL {
        #if os(macOS)
        return url
        #else
        if isInsideSandbox(url) { return url }
        var source = url
        var stale = false
        if let data = bookmarks[url.path],
           let resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            source = resolved
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        if let data = try? source.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmarks[url.path] = data
        }
        let key = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(12)
        let dir = AppPaths.support.appendingPathComponent("Working/\(key)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let working = dir.appendingPathComponent(source.lastPathComponent)
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordError) { src in
            do {
                let data = try Data(contentsOf: src)
                try data.write(to: working, options: .atomic)
            } catch { copyError = error }
        }
        if let e = coordError ?? copyError { throw e }
        originals[working.path] = source
        return working
        #endif
    }

    /// Writes the engine's copy back to the original file (no-op on macOS and for files in the sandbox).
    static func writeBack(_ enginePath: String?) throws {
        #if os(iOS)
        guard let enginePath, let original = originals[enginePath] else { return }
        let working = URL(fileURLWithPath: enginePath)
        let scoped = original.startAccessingSecurityScopedResource()
        defer { if scoped { original.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: working)
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: original, options: .forReplacing, error: &coordError) { dest in
            do { try data.write(to: dest) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
        #endif
    }

    /// The path to show and to remember for an open file.
    static func displayPath(_ enginePath: String) -> String {
        #if os(iOS)
        return originals[enginePath]?.path ?? enginePath
        #else
        return enginePath
        #endif
    }
}

// MARK: - Presenters (iOS)

#if os(iOS)
/// Presents the model's dialogs, pickers and exports. Attached once to the root view.
struct PlatformPresenters: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .alert(model.dialog?.title ?? "", isPresented: Binding(
                get: { model.dialog != nil },
                set: { if !$0 { model.dialog?.resume(max(0, (model.dialog?.buttons.count ?? 1) - 1)); model.dialog = nil } }
            ), presenting: model.dialog) { d in
                ForEach(Array(d.buttons.enumerated()), id: \.offset) { i, title in
                    Button(title, role: i == d.buttons.count - 1 && d.buttons.count > 1 ? .cancel : nil) {
                        d.resume(i)
                        model.dialog = nil
                    }
                }
            } message: { d in
                if let m = d.message { Text(m) }
            }
            .fileImporter(isPresented: $model.showFilePicker, allowedContentTypes: model.filePick?.types ?? [.item]) { result in
                let url = try? result.get()
                // Keep access to the picked file for the rest of the session: the engine reads it directly.
                _ = url?.startAccessingSecurityScopedResource()
                model.filePick?.resume(url)
                model.filePick = nil
            }
            .onChange(of: model.showFilePicker) { _, shown in
                // Cancelled (or closed before the completion arrived): answer nil a moment later.
                guard !shown, let r = model.filePick else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    r.resume(nil)
                    if model.filePick?.id == r.id { model.filePick = nil }
                }
            }
            .sheet(item: $model.exportRequest) { req in
                DocumentExporter(urls: req.urls).ignoresSafeArea()
            }
            .sheet(isPresented: $model.showSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L("Fatto")) { model.showSettings = false }
                            }
                        }
                }
                .environment(model)
            }
    }
}

/// "Save to Files" for one or more files (a copy; the originals stay where they are).
struct DocumentExporter: UIViewControllerRepresentable {
    var urls: [URL]
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: urls, asCopy: true)
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
}
#endif

extension View {
    /// iOS: presents dialogs, pickers, exports and Settings requested by the model. macOS: nothing.
    @ViewBuilder func platformPresenters() -> some View {
        #if os(iOS)
        modifier(PlatformPresenters()).modifier(PKSizeClassReader())
        #else
        self
        #endif
    }
}
