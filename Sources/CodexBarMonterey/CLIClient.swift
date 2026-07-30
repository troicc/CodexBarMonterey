@preconcurrency import Foundation

actor CLIClient {
    enum ClientError: LocalizedError {
        case helperMissing
        case launchFailed(String)
        case commandFailed(Int32, String)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing:
                return "Bundled CodexBarCLI helper is missing."
            case let .launchFailed(message):
                return "Could not launch CodexBarCLI: \(message)"
            case let .commandFailed(code, message):
                return "CodexBarCLI exited with code \(code): \(message)"
            case let .invalidJSON(message):
                return "CodexBarCLI returned invalid JSON: \(message)"
            }
        }
    }

    private let executableURL: URL

    init(bundle: Bundle = .main) {
        if let bundled = bundle.url(forAuxiliaryExecutable: "CodexBarCLI") {
            self.executableURL = bundled
        } else {
            self.executableURL = bundle.bundleURL
                .appendingPathComponent("Contents/Helpers/CodexBarCLI")
        }
    }

    /// Fetches the providers enabled in the same config file used by upstream CodexBar.
    /// Do not pass `--provider all` here: that forces unconfigured providers to launch and
    /// diverges from the menu-bar app's normal behavior.
    func fetchEnabled(status: Bool = true) async throws -> [ProviderSnapshot] {
        var arguments = ["--format", "json", "--json-only"]
        if status { arguments.append("--status") }
        let result = try await run(arguments: arguments, timeout: 120, acceptNonZero: true)
        guard !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.commandFailed(result.status, result.stderr)
        }
        do {
            return try Self.decodeSnapshots(result.stdout)
        } catch {
            if result.status != 0 {
                throw ClientError.commandFailed(result.status, result.stderr.isEmpty ? result.stdout : result.stderr)
            }
            throw error
        }
    }

    /// Uses upstream's own provider-specific text renderer. This preserves details that do
    /// not fit the shared UsageSnapshot shape (balances, routing stats, activity, etc.).
    func detailedText(provider: String? = nil) async throws -> String {
        var arguments = ["--no-color", "--status"]
        if let provider { arguments += ["--provider", provider] }
        let result = try await run(arguments: arguments, timeout: 120, acceptNonZero: true)
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        throw ClientError.commandFailed(result.status, result.stderr)
    }

    func costText(provider: String? = nil) async throws -> String {
        var arguments = ["cost", "--no-color"]
        if let provider { arguments += ["--provider", provider] }
        let result = try await run(arguments: arguments, timeout: 180, acceptNonZero: true)
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        throw ClientError.commandFailed(result.status, result.stderr)
    }

    func listProviders() async throws -> [ProviderDescriptor] {
        // Prefer the current machine-readable command, then retain a text fallback for
        // older upstream tags so the shell can follow the engine without a lockstep UI patch.
        if let result = try? await run(
            arguments: ["config", "providers", "--json"],
            timeout: 30),
           let descriptors = Self.decodeProviderDescriptors(result.stdout),
           !descriptors.isEmpty
        {
            return descriptors
        }
        let result = try await run(arguments: ["config", "providers"], timeout: 30)
        if let descriptors = Self.decodeProviderDescriptors(result.stdout), !descriptors.isEmpty {
            return descriptors
        }
        let parsed = Self.parseProviderText(result.stdout)
        if !parsed.isEmpty { return parsed }
        throw ClientError.invalidJSON("Could not parse `config providers` output")
    }

    func setProvider(_ id: String, enabled: Bool) async throws {
        _ = try await run(arguments: ["config", enabled ? "enable" : "disable", "--provider", id], timeout: 30)
    }

    func setAPIKey(_ key: String, provider: String) async throws {
        _ = try await run(
            arguments: ["config", "set-api-key", "--provider", provider, "--stdin"],
            stdin: key,
            timeout: 30)
    }

    func refreshBrowserSession(provider: String) async throws -> String {
        let result = try await run(
            arguments: ["cookie", "refresh", "--provider", provider, "--allow-keychain-prompt"],
            timeout: 120)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearBrowserSession(provider: String) async throws -> String {
        let result = try await run(
            arguments: ["cache", "clear", "--cookies", "--provider", provider],
            timeout: 30)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validateConfig() async throws -> String {
        try await run(arguments: ["config", "validate", "--format", "json", "--pretty"], timeout: 30).stdout
    }

    func version() async throws -> String {
        try await run(arguments: ["--version"], timeout: 15).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(
        arguments: [String],
        stdin: String? = nil,
        timeout: TimeInterval,
        acceptNonZero: Bool = false
    ) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ClientError.helperMissing
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = Self.loginEnvironment()

            // Use temporary files rather than pipes. Querying many enabled providers can
            // produce more output than a pipe buffer, which would deadlock if the parent
            // waited for process termination before draining stdout/stderr.
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexBarMonterey-\(UUID().uuidString)", isDirectory: true)
            let stdoutURL = temporaryDirectory.appendingPathComponent("stdout")
            let stderrURL = temporaryDirectory.appendingPathComponent("stderr")
            do {
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                _ = FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
                _ = FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            } catch {
                continuation.resume(throwing: ClientError.launchFailed(error.localizedDescription))
                return
            }

            let outputHandle: FileHandle
            let errorHandle: FileHandle
            do {
                outputHandle = try FileHandle(forWritingTo: stdoutURL)
                errorHandle = try FileHandle(forWritingTo: stderrURL)
            } catch {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                continuation.resume(throwing: ClientError.launchFailed(error.localizedDescription))
                return
            }
            process.standardOutput = outputHandle
            process.standardError = errorHandle

            if let stdin {
                let inputPipe = Pipe()
                process.standardInput = inputPipe
                inputPipe.fileHandleForWriting.write(Data(stdin.utf8))
                inputPipe.fileHandleForWriting.closeFile()
            }

            let completionGate = CompletionGate()
            let finish: @Sendable (Result<CommandResult, Error>) -> Void = { result in
                guard completionGate.claim() else { return }
                continuation.resume(with: result)
            }

            process.terminationHandler = { process in
                try? outputHandle.close()
                try? errorHandle.close()
                let stdoutData = (try? Data(contentsOf: stdoutURL)) ?? Data()
                let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
                try? FileManager.default.removeItem(at: temporaryDirectory)
                let stdout = String(decoding: stdoutData, as: UTF8.self)
                let stderr = String(decoding: stderrData, as: UTF8.self)
                let result = CommandResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
                if process.terminationStatus == 0 || acceptNonZero {
                    finish(.success(result))
                } else {
                    finish(.failure(ClientError.commandFailed(
                        process.terminationStatus,
                        stderr.isEmpty ? stdout : stderr)))
                }
            }

            do {
                try process.run()
            } catch {
                try? outputHandle.close()
                try? errorHandle.close()
                try? FileManager.default.removeItem(at: temporaryDirectory)
                finish(.failure(ClientError.launchFailed(error.localizedDescription)))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard completionGate.isPending else { return }
                process.terminate()
                finish(.failure(ClientError.commandFailed(124, "Timed out after \(Int(timeout)) seconds")))
            }
        }
    }

    private static func decodeSnapshots(_ json: String) throws -> [ProviderSnapshot] {
        let data = Data(json.utf8)
        do {
            let root = try JSONSerialization.jsonObject(with: data)
            if let rows = root as? [[String: Any]] {
                return try rows.map { row in
                    let itemData = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                    let decoded = try JSONCoding.decoder.decode(ProviderSnapshot.self, from: itemData)
                    return attachingRawJSON(decoded, source: String(decoding: itemData, as: UTF8.self))
                }
            }
            if let row = root as? [String: Any] {
                for key in ["providers", "results", "usage", "snapshots"] {
                    if let nested = row[key] as? [[String: Any]] {
                        return try nested.map { item in
                            let itemData = try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys])
                            let decoded = try JSONCoding.decoder.decode(ProviderSnapshot.self, from: itemData)
                            return attachingRawJSON(decoded, source: String(decoding: itemData, as: UTF8.self))
                        }
                    }
                }
                let decoded = try JSONCoding.decoder.decode(ProviderSnapshot.self, from: data)
                return [attachingRawJSON(decoded, source: json)]
            }
            throw ClientError.invalidJSON("Unsupported root shape")
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.invalidJSON(error.localizedDescription)
        }
    }

    private static func attachingRawJSON(_ snapshot: ProviderSnapshot, source: String) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: snapshot.provider,
            version: snapshot.version,
            source: snapshot.source,
            status: snapshot.status,
            usage: snapshot.usage,
            credits: snapshot.credits,
            account: snapshot.account,
            plan: snapshot.plan,
            error: snapshot.error,
            rawJSON: source)
    }

    private static func decodeProviderDescriptors(_ json: String) -> [ProviderDescriptor]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let rows: [[String: Any]]
        if let array = root as? [[String: Any]] {
            rows = array
        } else if let dictionary = root as? [String: Any], let array = dictionary["providers"] as? [[String: Any]] {
            rows = array
        } else {
            return nil
        }
        return rows.compactMap { row in
            guard let id = (row["id"] ?? row["provider"]) as? String else { return nil }
            let name = (row["name"] as? String) ?? ProviderCatalog.displayName(for: id)
            let enabled = (row["enabled"] as? Bool) ?? false
            return ProviderDescriptor(id: id, name: name, enabled: enabled)
        }
    }

    private static func parseProviderText(_ text: String) -> [ProviderDescriptor] {
        text.split(separator: "\n").compactMap { line in
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !value.lowercased().hasPrefix("provider") else { return nil }

            let lower = value.lowercased()
            let enabled = lower.contains("enabled") || value.hasPrefix("[x]") || value.hasPrefix("✓") || value.hasPrefix("●")
            for marker in ["[x]", "[ ]", "✓", "○", "●", "enabled", "disabled"] {
                value = value.replacingOccurrences(of: marker, with: "", options: [.caseInsensitive])
            }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)

            // Upstream commonly prints the stable ID first. Ignore punctuation around it.
            guard let token = value.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == ":" }).first else { return nil }
            let id = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "-–—:|"))
            guard !id.isEmpty, id.range(of: "^[a-z0-9][a-z0-9_-]*$", options: .regularExpression) != nil else { return nil }
            return ProviderDescriptor(id: id, name: ProviderCatalog.displayName(for: id), enabled: enabled)
        }
    }

    private static func loginEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let commonPaths = [
            "/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.npm-global/bin", "\(NSHomeDirectory())/.volta/bin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = (commonPaths + [currentPath]).joined(separator: ":")
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        return environment
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !completed
    }

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}

private struct CommandResult {
    let stdout: String
    let stderr: String
    let status: Int32
}
