import Foundation

struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to the PkMacEngine process (PKHeX.Core host) over stdin/stdout, one JSON object per line.
final class EngineClient: @unchecked Sendable {
    let executable: URL
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private let lock = NSLock()

    /// Unsolicited events (e.g. progress) from the engine.
    var onEvent: (@Sendable (String, [String: Any]) -> Void)?
    /// Called if the engine process exits unexpectedly.
    var onExit: (@Sendable (Int32) -> Void)?

    init(executable: URL) {
        self.executable = executable
    }

    var isRunning: Bool { process?.isRunning == true }

    func start() throws {
        let p = Process()
        p.executableURL = executable
        p.currentDirectoryURL = executable.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
        env["DOTNET_gcServer"] = "0"
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            if chunk.isEmpty { return }
            self?.consume(chunk)
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if let s = String(data: chunk, encoding: .utf8), !s.isEmpty {
                Log.engine(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.failAll(EngineError(message: "Il motore PKHeX si è chiuso (codice \(proc.terminationStatus))."))
            self.onExit?(proc.terminationStatus)
        }
        try p.run()
        process = p
        stdin = inPipe.fileHandleForWriting
    }

    func stop() {
        if let stdin, isRunning {
            try? stdin.write(contentsOf: Data("{\"id\":0,\"method\":\"quit\"}\n".utf8))
        }
        process?.terminationHandler = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [process] in
            if process?.isRunning == true { process?.terminate() }
        }
        process = nil
    }

    // MARK: requests

    func call<T: Decodable>(_ method: String, _ params: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        let data = try await raw(method, params)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Log.app("decode \(method) failed: \(error)\n\(String(data: data, encoding: .utf8)?.prefix(800) ?? "")")
            throw EngineError(message: "Risposta inattesa dal motore (\(method)).")
        }
    }

    @discardableResult
    func send(_ method: String, _ params: [String: Any] = [:]) async throws -> Data {
        try await raw(method, params)
    }

    private func raw(_ method: String, _ params: [String: Any]) async throws -> Data {
        guard let stdin, isRunning else { throw EngineError(message: "Il motore PKHeX non è in esecuzione.") }
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            let id = nextID
            nextID += 1
            pending[id] = cont
            lock.unlock()
            do {
                let req: [String: Any] = ["id": id, "method": method, "params": params]
                var line = try JSONSerialization.data(withJSONObject: req)
                line.append(0x0A)
                try stdin.write(contentsOf: line)
            } catch {
                lock.lock(); pending[id] = nil; lock.unlock()
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: responses

    private func consume(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: buffer.startIndex..<nl))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines where !line.isEmpty { handle(line) }
    }

    private func handle(_ line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let event = obj["event"] as? String {
            onEvent?(event, obj["data"] as? [String: Any] ?? [:])
            return
        }
        guard let id = obj["id"] as? Int else { return }
        lock.lock()
        let cont = pending.removeValue(forKey: id)
        lock.unlock()
        guard let cont else { return }
        if let err = obj["error"] as? String {
            cont.resume(throwing: EngineError(message: err))
        } else {
            let result = obj["result"] ?? NSNull()
            let data = (try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed])) ?? Data("null".utf8)
            cont.resume(returning: data)
        }
    }

    private func failAll(_ error: Error) {
        lock.lock()
        let all = pending
        pending.removeAll()
        lock.unlock()
        for (_, c) in all { c.resume(throwing: error) }
    }
}

enum Log {
    static func engine(_ s: String) { print("[engine] \(s)") }
    static func app(_ s: String) { print("[app] \(s)") }
}
