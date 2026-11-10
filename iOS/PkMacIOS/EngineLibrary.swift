import Darwin
import Foundation

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The PkMac engine on iOS/iPadOS: PkMacEngine.framework (PKHeX.Core + plugins compiled with NativeAOT),
/// loaded in the app's own process. Same JSON lines as the macOS engine process, through C calls.
final class EngineClient: @unchecked Sendable {
    private typealias CallFn = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
    private typealias FreeFn = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private typealias SetEventsFn = @convention(c) ((@convention(c) (UnsafePointer<CChar>?) -> Void)?) -> Void

    private var callFn: CallFn?
    private var freeFn: FreeFn?
    private var nextID = 1
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.pkmac.engine", qos: .userInitiated, attributes: .concurrent)

    /// Unsolicited events (e.g. progress) from the engine.
    var onEvent: (@Sendable (String, [String: Any]) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    nonisolated(unsafe) private static weak var current: EngineClient?
    nonisolated(unsafe) private static var loaded: UnsafeMutableRawPointer?

    /// The framework binary (…/Frameworks/PkMacEngine.framework/PkMacEngine), as given by EngineManager.executable().
    let executable: URL

    init(executable: URL) { self.executable = executable }

    convenience init() {
        let fw = Bundle.main.privateFrameworksURL ?? Bundle.main.bundleURL.appendingPathComponent("Frameworks")
        self.init(executable: fw.appendingPathComponent("PkMacEngine.framework/PkMacEngine"))
    }

    var isRunning: Bool { callFn != nil }

    func start() throws {
        let path = executable.path
        guard FileManager.default.fileExists(atPath: path) else { throw EngineError(message: "Motore PKHeX non incluso nell'app") }
        // The runtime can be loaded only once per process: a "restart" reuses the same library.
        guard let handle = EngineClient.loaded ?? dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw EngineError(message: dlerror().map { String(cString: $0) } ?? "dlopen non riuscito")
        }
        guard let c = dlsym(handle, "pkmac_call"), let f = dlsym(handle, "pkmac_free"), let e = dlsym(handle, "pkmac_set_event_callback") else {
            throw EngineError(message: "Funzioni del motore mancanti")
        }
        EngineClient.loaded = handle
        callFn = unsafeBitCast(c, to: CallFn.self)
        freeFn = unsafeBitCast(f, to: FreeFn.self)
        EngineClient.current = self
        let setEvents = unsafeBitCast(e, to: SetEventsFn.self)
        setEvents { pointer in
            guard let pointer, let client = EngineClient.current,
                  let obj = try? JSONSerialization.jsonObject(with: Data(bytes: pointer, count: strlen(pointer))) as? [String: Any],
                  let name = obj["event"] as? String else { return }
            client.onEvent?(name, obj["data"] as? [String: Any] ?? [:])
        }
    }

    /// The in-process engine can't be unloaded: stopping just detaches this client.
    func stop() {
        callFn = nil
        freeFn = nil
        if EngineClient.current === self { EngineClient.current = nil }
    }

    func call<T: Decodable>(_ method: String, _ params: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await raw(method, params)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw EngineError(message: "Risposta inattesa dal motore (\(method)): \(error)") }
    }

    @discardableResult
    func send(_ method: String, _ params: [String: Any] = [:]) async throws -> Data {
        try await raw(method, params)
    }

    private func makeID() -> Int {
        lock.lock(); defer { lock.unlock() }
        let id = nextID; nextID += 1
        return id
    }

    private func raw(_ method: String, _ params: [String: Any]) async throws -> Data {
        guard let callFn, let freeFn else { throw EngineError(message: "Il motore PKHeX non è caricato.") }
        let id = makeID()
        let req: [String: Any] = ["id": id, "method": method, "params": params]
        let line = String(decoding: try JSONSerialization.data(withJSONObject: req), as: UTF8.self)
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                guard let out = line.withCString({ callFn($0) }) else {
                    cont.resume(throwing: EngineError(message: "Nessuna risposta dal motore")); return
                }
                let data = Data(bytes: out, count: strlen(out))
                freeFn(out)
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    cont.resume(throwing: EngineError(message: "Risposta del motore non valida")); return
                }
                if let err = obj["error"] as? String { cont.resume(throwing: EngineError(message: err)); return }
                let result = obj["result"] ?? NSNull()
                do { cont.resume(returning: try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}
