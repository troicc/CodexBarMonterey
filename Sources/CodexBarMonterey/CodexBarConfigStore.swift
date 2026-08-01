import Foundation

enum CodexBarConfigStoreError: LocalizedError {
    case invalidRoot
    case unsupportedStorage(String)
    case missingSecret(String)
    case missingField(String)
    case noConfigurationValues
    case invalidXDGPath(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoot:
            return "The CodexBar config root is not a JSON object."
        case let .unsupportedStorage(provider):
            return "\(ProviderCatalog.displayName(for: provider)) does not store a credential in the CodexBar config file."
        case let .missingSecret(label):
            return "\(label) is required."
        case let .missingField(label):
            return "\(label) is required."
        case .noConfigurationValues:
            return "Enter at least one provider configuration value."
        case let .invalidXDGPath(path):
            return "XDG_CONFIG_HOME must be an absolute path; received \(path)."
        }
    }
}

struct CodexBarConfigBackup {
    fileprivate let url: URL
    fileprivate let contents: Data?
}

final class CodexBarConfigStore {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func resolvedConfigURL() throws -> URL {
        if let override = trimmed(environment["CODEXBAR_CONFIG"]), !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }

        if let xdg = trimmed(environment["XDG_CONFIG_HOME"]), !xdg.isEmpty {
            guard xdg.hasPrefix("/") else {
                throw CodexBarConfigStoreError.invalidXDGPath(xdg)
            }
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("codexbar/config.json")
        }

        let current = homeDirectory.appendingPathComponent(".config/codexbar/config.json")
        let legacy = homeDirectory.appendingPathComponent(".codexbar/config.json")
        if fileManager.fileExists(atPath: current.path) {
            return current
        }
        if fileManager.fileExists(atPath: legacy.path) {
            return legacy
        }
        return current
    }

    func ensureConfigFile() throws -> URL {
        let url = try resolvedConfigURL()
        if !fileManager.fileExists(atPath: url.path) {
            let root: [String: Any] = [
                "version": 1,
                "hooks": NSNull(),
                "providers": [],
            ]
            try write(root: root, to: url)
        }
        return url
    }

    func makeBackup() throws -> CodexBarConfigBackup {
        let url = try resolvedConfigURL()
        let contents = fileManager.fileExists(atPath: url.path)
            ? try Data(contentsOf: url)
            : nil
        return CodexBarConfigBackup(url: url, contents: contents)
    }

    func restore(_ backup: CodexBarConfigBackup) throws {
        if let contents = backup.contents {
            try fileManager.createDirectory(
                at: backup.url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try contents.write(to: backup.url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backup.url.path)
        } else if fileManager.fileExists(atPath: backup.url.path) {
            try fileManager.removeItem(at: backup.url)
        }
    }

    func save(
        providerID: String,
        profile: ProviderAuthenticationProfile,
        input: ProviderCredentialInput
    ) throws -> CredentialSaveReceipt {
        guard profile.storage != .external else {
            throw CodexBarConfigStoreError.unsupportedStorage(providerID)
        }

        let url = try ensureConfigFile()
        var root = try readRoot(from: url)
        var providers = root["providers"] as? [[String: Any]] ?? []

        let index: Int
        if let existing = providers.firstIndex(where: { ($0["id"] as? String) == providerID }) {
            index = existing
        } else {
            providers.append(["id": providerID])
            index = providers.count - 1
        }

        var provider = providers[index]
        provider["id"] = providerID
        provider["enabled"] = true

        let secret = input.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        switch profile.storage {
        case .apiKey:
            guard !secret.isEmpty else {
                throw CodexBarConfigStoreError.missingSecret(profile.secretLabel)
            }
            provider["apiKey"] = secret

        case .tokenAccount:
            guard !secret.isEmpty else {
                throw CodexBarConfigStoreError.missingSecret(profile.secretLabel)
            }
            provider["tokenAccounts"] = updatedTokenAccounts(
                existing: provider["tokenAccounts"],
                token: secret,
                requestedLabel: input.accountLabel)

        case .manualCookie:
            guard !secret.isEmpty else {
                throw CodexBarConfigStoreError.missingSecret(profile.secretLabel)
            }
            provider["cookieSource"] = "manual"
            provider["cookieHeader"] = normalizedManualCredential(secret)

        case .providerFields:
            let hasValue = !input.enterpriseHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !input.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !input.region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasValue else {
                throw CodexBarConfigStoreError.noConfigurationValues
            }

        case .external:
            throw CodexBarConfigStoreError.unsupportedStorage(providerID)
        }

        try applyOptionalFields(profile: profile, input: input, provider: &provider)
        providers[index] = provider
        root["version"] = (root["version"] as? Int) ?? 1
        root["providers"] = providers
        try write(root: root, to: url)

        return CredentialSaveReceipt(configURL: url)
    }

    private func applyOptionalFields(
        profile: ProviderAuthenticationProfile,
        input: ProviderCredentialInput,
        provider: inout [String: Any]
    ) throws {
        let host = input.enterpriseHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = input.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = input.region.trimmingCharacters(in: .whitespacesAndNewlines)

        if profile.enterpriseHostRequired && host.isEmpty {
            throw CodexBarConfigStoreError.missingField(profile.enterpriseHostLabel ?? "Base URL")
        }
        if profile.workspaceRequired && workspace.isEmpty {
            throw CodexBarConfigStoreError.missingField(profile.workspaceLabel ?? "Workspace ID")
        }

        if !host.isEmpty {
            provider["enterpriseHost"] = host
        }
        if !workspace.isEmpty {
            provider["workspaceID"] = workspace
        }
        if !region.isEmpty {
            provider["region"] = region
        }
    }

    private func readRoot(from url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return ["version": 1, "hooks": NSNull(), "providers": []]
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty {
            return ["version": 1, "hooks": NSNull(), "providers": []]
        }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw CodexBarConfigStoreError.invalidRoot
        }
        return root
    }

    private func write(root: [String: Any], to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys])
        var output = data
        output.append(0x0A)
        try output.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path)
    }

    private func updatedTokenAccounts(
        existing: Any?,
        token: String,
        requestedLabel: String
    ) -> [String: Any] {
        var container = existing as? [String: Any] ?? [:]
        var accounts = container["accounts"] as? [[String: Any]] ?? []
        let label = requestedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? "Default" : label
        let now = Int(Date().timeIntervalSince1970)

        let accountIndex: Int
        if let existingIndex = accounts.firstIndex(where: {
            (($0["label"] as? String) ?? "").caseInsensitiveCompare(resolvedLabel) == .orderedSame
        }) {
            accountIndex = existingIndex
            var account = accounts[existingIndex]
            account["token"] = token
            account["label"] = resolvedLabel
            account["lastUsed"] = now
            if account["id"] == nil {
                account["id"] = UUID().uuidString.lowercased()
            }
            if account["addedAt"] == nil {
                account["addedAt"] = now
            }
            accounts[existingIndex] = account
        } else {
            accountIndex = accounts.count
            accounts.append([
                "id": UUID().uuidString.lowercased(),
                "label": resolvedLabel,
                "token": token,
                "addedAt": now,
                "lastUsed": now,
            ])
        }

        container["version"] = 1
        container["activeIndex"] = accountIndex
        container["accounts"] = accounts
        return container
    }

    private func normalizedManualCredential(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.lowercased().hasPrefix("cookie:") {
            return String(trimmedValue.dropFirst("cookie:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmedValue
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
