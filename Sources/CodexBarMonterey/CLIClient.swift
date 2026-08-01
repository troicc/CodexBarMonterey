@preconcurrency import Foundation

actor CLIClient {
    enum ClientError: LocalizedError {
        case helperMissing
        case launchFailed(String)
        case commandFailed(Int32, String)
        case invalidJSON(String)
        case configurationRejected(String)
        case rollbackFailed(operation: String, rollback: String)

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
            case let .configurationRejected(message):
                return "Configuration was not applied; the previous configuration was restored: \(message)"
            case let .rollbackFailed(operation, rollback):
                return "Configuration update failed (\(operation)) and the previous configuration could not be restored (\(rollback))."
            }
        }
    }

    private let executableURL: URL
    private let configStore: CodexBarConfigStore

    init(
        bundle: Bundle = .main,
        configStore: CodexBarConfigStore = CodexBarConfigStore()
    ) {
        self.configStore = configStore
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
        let result = try await run(
            arguments: arguments,
            timeout: 120,
            acceptNonZero: true,
            includeLiveUsage: true)
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

    /// Returns provider-specific usage/cost JSON for the graphical dashboard.
    /// Some providers expose their history in the usage payload, while local
    /// Codex/Claude scans expose it through `cost`; both are accepted here.
    func dashboardSupplementJSON(provider: String) async -> String? {
        // The enabled-provider fetch already supplies the complete raw usage JSON.
        // Only Codex and Claude require the separate local cost-history payload.
        // Combining another usage payload with cost JSON made generic field
        // discovery select daily totals as if they were 30-day aggregates.
        guard provider == "codex" || provider == "claude" else { return nil }
        guard let result = try? await run(
            arguments: ["cost", "--provider", provider, "--format", "json", "--pretty"],
            timeout: 180,
            acceptNonZero: true)
        else { return nil }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return nil }
        return text
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

    func saveCredential(
        _ input: ProviderCredentialInput,
        provider: String,
        profile: ProviderAuthenticationProfile
    ) async throws -> CredentialSaveReceipt {
        let backup = try configStore.makeBackup()
        do {
            let receipt = try configStore.save(
                providerID: provider,
                profile: profile,
                input: input)
            _ = try await run(
                arguments: ["config", "validate", "--format", "json", "--pretty"],
                timeout: 30)
            _ = try await probeProvider(provider, profile: profile)
            return receipt
        } catch {
            do {
                try configStore.restore(backup)
            } catch let rollbackError {
                NSLog("Provider configuration rollback failed for %@", provider)
                throw ClientError.rollbackFailed(
                    operation: error.localizedDescription,
                    rollback: rollbackError.localizedDescription)
            }
            NSLog("Provider configuration update rejected for %@; restored previous configuration", provider)
            throw ClientError.configurationRejected(error.localizedDescription)
        }
    }

    func configuredAccounts(provider: String) throws -> [ConfiguredProviderAccount] {
        try configStore.configuredTokenAccounts(providerID: provider)
    }

    func activateConfiguredAccount(
        provider: String,
        accountID: String,
        profile: ProviderAuthenticationProfile
    ) async throws {
        let backup = try configStore.makeBackup()
        do {
            try configStore.activateTokenAccount(providerID: provider, accountID: accountID)
            _ = try await run(
                arguments: ["config", "validate", "--format", "json", "--pretty"],
                timeout: 30)
            _ = try await probeProvider(provider, profile: profile)
        } catch {
            do { try configStore.restore(backup) }
            catch let rollbackError {
                throw ClientError.rollbackFailed(
                    operation: error.localizedDescription,
                    rollback: rollbackError.localizedDescription)
            }
            throw ClientError.configurationRejected(error.localizedDescription)
        }
    }

    func removeConfiguredAccount(provider: String, accountID: String) async throws {
        let backup = try configStore.makeBackup()
        do {
            try configStore.removeTokenAccount(providerID: provider, accountID: accountID)
            _ = try await run(
                arguments: ["config", "validate", "--format", "json", "--pretty"],
                timeout: 30)
        } catch {
            do { try configStore.restore(backup) }
            catch let rollbackError {
                throw ClientError.rollbackFailed(
                    operation: error.localizedDescription,
                    rollback: rollbackError.localizedDescription)
            }
            throw ClientError.configurationRejected(error.localizedDescription)
        }
    }

    func probeProvider(
        _ provider: String,
        profile: ProviderAuthenticationProfile
    ) async throws -> String {
        var arguments = ["--no-color", "--provider", provider]
        if let source = profile.probeSource {
            arguments += ["--source", source]
        }
        let result = try await run(arguments: arguments, timeout: 90)
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Provider verification completed successfully." : text
    }

    func configFileURL() throws -> URL {
        try configStore.ensureConfigFile()
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
        timeout: TimeInterval,
        acceptNonZero: Bool = false,
        includeLiveUsage: Bool = false
    ) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ClientError.helperMissing
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            var environment = Self.loginEnvironment()
            if includeLiveUsage {
                environment["CODEXBAR_MONTEREY_INCLUDE_LIVE_USAGE"] = "1"
            }
            process.environment = environment

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
