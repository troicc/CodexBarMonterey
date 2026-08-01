import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let temp = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexBarProviderAuth-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }

let configURL = temp.appendingPathComponent("config.json")
let initial: [String: Any] = [
    "version": 1,
    "hooks": ["enabled": false],
    "unknownRoot": "preserve-me",
    "providers": [
        [
            "id": "codex",
            "enabled": true,
            "unknownProviderField": "keep-me",
        ],
    ],
]
let initialData = try JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted])
try initialData.write(to: configURL)

let store = CodexBarConfigStore(
    environment: ["CODEXBAR_CONFIG": configURL.path],
    homeDirectory: temp)

func input(
    secret: String = "",
    label: String = "Default",
    host: String = "",
    workspace: String = "",
    region: String = ""
) -> ProviderCredentialInput {
    ProviderCredentialInput(
        secret: secret,
        accountLabel: label,
        enterpriseHost: host,
        workspaceID: workspace,
        region: region)
}

let deepseek = ProviderAuthenticationCatalog.profile(for: "deepseek")
expect(deepseek.storage == .tokenAccount, "DeepSeek must use tokenAccounts")
_ = try store.save(
    providerID: "deepseek",
    profile: deepseek,
    input: input(secret: "sk-deepseek-test", label: "Primary"))

let openrouter = ProviderAuthenticationCatalog.profile(for: "openrouter")
expect(openrouter.storage == .apiKey, "OpenRouter must use apiKey")
_ = try store.save(
    providerID: "openrouter",
    profile: openrouter,
    input: input(secret: "sk-or-test"))

let llmproxy = ProviderAuthenticationCatalog.profile(for: "llmproxy")
_ = try store.save(
    providerID: "llmproxy",
    profile: llmproxy,
    input: input(secret: "proxy-key", host: "https://proxy.example.com"))

let cursor = ProviderAuthenticationCatalog.profile(for: "cursor")
_ = try store.save(
    providerID: "cursor",
    profile: cursor,
    input: input(secret: "Cookie: session=abc; other=def"))

let moonshot = ProviderAuthenticationCatalog.profile(for: "moonshot")
_ = try store.save(
    providerID: "moonshot",
    profile: moonshot,
    input: input(secret: "moonshot-key", region: "china"))

let data = try Data(contentsOf: configURL)
guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let providers = root["providers"] as? [[String: Any]]
else {
    fail("Could not decode written config")
}

func provider(_ id: String) -> [String: Any] {
    guard let row = providers.first(where: { ($0["id"] as? String) == id }) else {
        fail("Missing provider \(id)")
    }
    return row
}

let deepseekRow = provider("deepseek")
expect(deepseekRow["apiKey"] == nil, "DeepSeek must not be written to apiKey")
guard let accountsRoot = deepseekRow["tokenAccounts"] as? [String: Any],
      let accounts = accountsRoot["accounts"] as? [[String: Any]],
      let first = accounts.first
else {
    fail("DeepSeek tokenAccounts missing")
}
expect(first["token"] as? String == "sk-deepseek-test", "DeepSeek token not saved")
expect(first["label"] as? String == "Primary", "DeepSeek label not saved")
expect(accountsRoot["activeIndex"] as? Int == 0, "DeepSeek activeIndex incorrect")

expect(provider("openrouter")["apiKey"] as? String == "sk-or-test", "OpenRouter apiKey missing")
expect(provider("llmproxy")["enterpriseHost"] as? String == "https://proxy.example.com", "LLM Proxy host missing")
expect(provider("cursor")["cookieSource"] as? String == "manual", "Cursor cookieSource missing")
expect(provider("cursor")["cookieHeader"] as? String == "session=abc; other=def", "Cookie prefix not normalized")
expect(provider("moonshot")["region"] as? String == "china", "Moonshot region missing")
expect(root["unknownRoot"] as? String == "preserve-me", "Unknown root field was lost")
expect(provider("codex")["unknownProviderField"] as? String == "keep-me", "Unknown provider field was lost")

let attributes = try FileManager.default.attributesOfItem(atPath: configURL.path)
if let permissions = attributes[.posixPermissions] as? NSNumber {
    expect(permissions.intValue & 0o777 == 0o600, "Config permissions are not 0600")
}

expect(ProviderAuthenticationCatalog.uncoveredStableProviderIDs.isEmpty,
       "Uncovered provider IDs: \(ProviderAuthenticationCatalog.uncoveredStableProviderIDs)")
expect(ProviderAuthenticationCatalog.profiles.count == ProviderAuthenticationCatalog.stableProviderIDs.count,
       "Authentication profile count does not match provider count")

// Save-and-verify uses this backup to roll back invalid credentials. Restoring
// must preserve unknown upstream fields as well as the previous credential.
let backup = try store.makeBackup()
_ = try store.save(
    providerID: "openrouter",
    profile: openrouter,
    input: input(secret: "replacement-that-must-roll-back"))
try store.restore(backup)
let restoredData = try Data(contentsOf: configURL)
guard let restoredRoot = try JSONSerialization.jsonObject(with: restoredData) as? [String: Any],
      let restoredProviders = restoredRoot["providers"] as? [[String: Any]],
      let restoredOpenRouter = restoredProviders.first(where: { ($0["id"] as? String) == "openrouter" })
else { fail("Could not decode restored config") }
expect(restoredOpenRouter["apiKey"] as? String == "sk-or-test", "Backup did not restore the previous API key")
expect(restoredRoot["unknownRoot"] as? String == "preserve-me", "Backup lost unknown root fields")

// If save created a brand-new config, rollback should remove it instead of
// leaving an unverified credential behind.
let newConfigURL = temp.appendingPathComponent("new-config.json")
let newStore = CodexBarConfigStore(
    environment: ["CODEXBAR_CONFIG": newConfigURL.path],
    homeDirectory: temp)
let absentBackup = try newStore.makeBackup()
_ = try newStore.save(
    providerID: "openrouter",
    profile: openrouter,
    input: input(secret: "temporary-key"))
expect(FileManager.default.fileExists(atPath: newConfigURL.path), "Test config was not created")
try newStore.restore(absentBackup)
expect(!FileManager.default.fileExists(atPath: newConfigURL.path), "Rollback did not remove a newly created config")

print("All-provider authentication/config regression tests passed.")
