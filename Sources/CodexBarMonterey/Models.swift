import Foundation

struct ProviderSnapshot: Decodable, Hashable, Identifiable {
    let provider: String
    let version: String?
    let source: String?
    let status: ProviderStatus?
    let usage: UsageSnapshot?
    let credits: CreditsSnapshot?
    let account: String?
    let plan: String?
    let error: ProviderError?
    let rawJSON: String?

    init(
        provider: String,
        version: String?,
        source: String?,
        status: ProviderStatus?,
        usage: UsageSnapshot?,
        credits: CreditsSnapshot?,
        account: String?,
        plan: String?,
        error: ProviderError?,
        rawJSON: String?)
    {
        self.provider = provider
        self.version = version
        self.source = source
        self.status = status
        self.usage = usage
        self.credits = credits
        self.account = account
        self.plan = plan
        self.error = error
        self.rawJSON = rawJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try container.decode(String.self, forKey: .provider)
        self.version = try? container.decodeIfPresent(String.self, forKey: .version)
        self.source = try? container.decodeIfPresent(String.self, forKey: .source)
        self.status = try? container.decodeIfPresent(ProviderStatus.self, forKey: .status)
        self.usage = try? container.decodeIfPresent(UsageSnapshot.self, forKey: .usage)
        self.credits = try? container.decodeIfPresent(CreditsSnapshot.self, forKey: .credits)
        self.account = try? container.decodeIfPresent(String.self, forKey: .account)
        self.plan = try? container.decodeIfPresent(String.self, forKey: .plan)
        self.error = try? container.decodeIfPresent(ProviderError.self, forKey: .error)
        self.rawJSON = nil
    }

    private enum CodingKeys: String, CodingKey {
        case provider, version, source, status, usage, credits, account, plan, error
    }

    var id: String {
        let providerComponent = provider.lowercased()
        let accountComponent = accountName?.lowercased() ?? "default"
        if let organization = accountOrganizationName {
            return "\(providerComponent)::\(accountComponent)::\(organization.lowercased())"
        }
        return "\(providerComponent)::\(accountComponent)"
    }

    var accountDisplayName: String? {
        switch (accountName, accountOrganizationName) {
        case let (account?, organization?) where account.caseInsensitiveCompare(organization) != .orderedSame:
            return "\(account) · \(organization)"
        case let (account?, _):
            return account
        case let (_, organization?):
            return organization
        default:
            return nil
        }
    }

    private var accountName: String? {
        Self.firstNonEmpty([
            usage?.identity?.accountEmail,
            usage?.accountEmail,
            account,
        ])
    }

    private var accountOrganizationName: String? {
        Self.firstNonEmpty([
            usage?.identity?.accountOrganization,
            usage?.accountOrganization,
        ])
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    var displayName: String {
        ProviderCatalog.displayName(for: provider)
    }

    var maximumUsedPercent: Double? {
        // DeepSeek API-key mode exposes a balance sentinel, not a real quota window.
        if provider == "deepseek" { return nil }
        let values = [usage?.primary?.usedPercent, usage?.secondary?.usedPercent, usage?.tertiary?.usedPercent]
            .compactMap { $0 }
        return values.max()
    }

    /// The single quota that should represent this provider in compact UI.
    /// z.ai exposes both its main five-hour allowance and secondary MCP/monthly
    /// windows. The main menu must not let a small MCP percentage replace the
    /// five-hour value simply because it happens to be numerically larger.
    var headlineQuotaWindow: RateWindow? {
        guard provider != "deepseek" else { return nil }
        let windows = [usage?.primary, usage?.secondary, usage?.tertiary].compactMap { $0 }
        guard provider == "zai" else {
            return windows.max {
                ($0.usedPercent ?? -1) < ($1.usedPercent ?? -1)
            }
        }
        if let fiveHour = windows.first(where: { window in
            guard let minutes = window.windowMinutes else { return false }
            return abs(minutes - 300) <= 1
        }) {
            return fiveHour
        }
        // Older engine payloads omit windowMinutes but put the main allowance
        // in primary. Secondary is commonly MCP and is not a safe fallback.
        return usage?.primary
    }

    var headlineUsedPercent: Double? {
        headlineQuotaWindow?.usedPercent
    }

    var headlineQuotaLabel: String? {
        guard provider == "zai", headlineQuotaWindow != nil else { return nil }
        return "5h"
    }

    var isFailed: Bool { error != nil }
}

enum StableIdentifier {
    static func hash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}

struct ProviderStatus: Decodable, Hashable {
    let indicator: String?
    let description: String?
    let updatedAt: Date?
    let url: URL?
}

enum ProviderServiceHealth: Int, Hashable, Comparable {
    case unknown = 0
    case operational = 1
    case degraded = 2
    case outage = 3

    static func < (lhs: ProviderServiceHealth, rhs: ProviderServiceHealth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .unknown: return "Status unavailable"
        case .operational: return "Operational"
        case .degraded: return "Degraded service"
        case .outage: return "Service outage"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .operational: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .outage: return "xmark.octagon.fill"
        }
    }

    var isIncident: Bool { self == .degraded || self == .outage }
}

extension ProviderStatus {
    var health: ProviderServiceHealth {
        let normalizedIndicator = indicator?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if ["critical", "major"].contains(normalizedIndicator) { return .outage }
        if ["minor", "degraded", "maintenance", "warning"].contains(normalizedIndicator) { return .degraded }
        if ["none", "operational", "ok", "up"].contains(normalizedIndicator) { return .operational }

        let normalized = [indicator, description]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return .unknown }
        if ["critical", "major", "outage", "down", "unavailable"].contains(where: normalized.contains) {
            return .outage
        }
        if ["minor", "degraded", "maintenance", "warning", "partial"].contains(where: normalized.contains) {
            return .degraded
        }
        if ["operational", "available", "all systems"].contains(where: normalized.contains) {
            return .operational
        }
        return .unknown
    }

    var displayText: String {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? health.title : trimmed
    }
}

extension ProviderSnapshot {
    var serviceHealth: ProviderServiceHealth { status?.health ?? .unknown }
    var hasVisibleAlert: Bool { error != nil || serviceHealth.isIncident }
}

struct UsageSnapshot: Decodable, Hashable {
    let primary: RateWindow?
    let secondary: RateWindow?
    let tertiary: RateWindow?
    let updatedAt: Date?
    let identity: UsageIdentity?
    let accountEmail: String?
    let accountOrganization: String?
    let loginMethod: String?
}

struct UsageIdentity: Decodable, Hashable {
    let providerID: String?
    let accountEmail: String?
    let accountOrganization: String?
    let loginMethod: String?
}

struct RateWindow: Decodable, Hashable {
    let usedPercent: Double?
    let windowMinutes: Double?
    let resetsAt: Date?

    var remainingPercent: Double? {
        guard let usedPercent = usedPercent else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
}

struct CreditsSnapshot: Decodable, Hashable {
    let remaining: Double?
    let updatedAt: Date?
    let hasCredits: Bool?
    let unlimited: Bool?
}

struct ProviderError: Decodable, Hashable {
    let message: String?
    let code: String?

    init(message: String?, code: String? = nil) {
        self.message = message
        self.code = code
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let message = try? single.decode(String.self)
        {
            self.init(message: message)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let message = (try? container.decode(String.self, forKey: .message)) ??
            (try? container.decode(String.self, forKey: .error))
        let code = try? container.decode(String.self, forKey: .code)
        self.init(message: message, code: code)
    }

    private enum CodingKeys: String, CodingKey {
        case message, error, code
    }
}

struct ProviderDescriptor: Hashable, Identifiable {
    let id: String
    let name: String
    let enabled: Bool
}

enum ProviderCatalog {
    // Exact stable IDs registered by CodexBar v0.46.0. The settings UI normally
    // obtains names dynamically from `config providers`; this table is only a
    // fallback for snapshots and older text output.
    private static let names: [String: String] = [
        "codex": "Codex",
        "openai": "OpenAI",
        "azureopenai": "Azure OpenAI",
        "claude": "Claude",
        "clinepass": "ClinePass",
        "cursor": "Cursor",
        "opencode": "OpenCode",
        "opencodego": "OpenCode Go",
        "alibaba": "Alibaba Coding Plan",
        "alibabatokenplan": "Alibaba Token Plan",
        "qwencloud": "Qwen Cloud",
        "factory": "Droid / Factory",
        "gemini": "Gemini",
        "antigravity": "Antigravity",
        "copilot": "GitHub Copilot",
        "devin": "Devin",
        "zai": "z.ai",
        "minimax": "MiniMax",
        "manus": "Manus",
        "kimi": "Kimi",
        "kilo": "Kilo",
        "kiro": "Kiro",
        "vertexai": "Vertex AI",
        "augment": "Augment",
        "jetbrains": "JetBrains AI",
        "moonshot": "Moonshot / Kimi API",
        "amp": "Amp",
        "t3chat": "T3 Chat",
        "ollama": "Ollama",
        "synthetic": "Synthetic",
        "warp": "Warp",
        "openrouter": "OpenRouter",
        "elevenlabs": "ElevenLabs",
        "windsurf": "Windsurf",
        "zed": "Zed",
        "perplexity": "Perplexity",
        "mimo": "Xiaomi MiMo",
        "doubao": "Doubao",
        "sakana": "Sakana AI",
        "abacus": "Abacus AI",
        "mistral": "Mistral",
        "deepseek": "DeepSeek",
        "deepinfra": "DeepInfra",
        "codebuff": "Codebuff",
        "crof": "Crof",
        "venice": "Venice",
        "commandcode": "Command Code",
        "qoder": "Qoder",
        "stepfun": "StepFun",
        "bedrock": "AWS Bedrock",
        "grok": "Grok",
        "groq": "GroqCloud",
        "llmproxy": "LLM Proxy",
        "litellm": "LiteLLM",
        "deepgram": "Deepgram",
        "poe": "Poe",
        "chutes": "Chutes",
        "neuralwatt": "Neuralwatt",
        "clawrouter": "ClawRouter",
        "longcat": "LongCat",
        "sub2api": "sub2api",
        "wayfinder": "Wayfinder",
        "zenmux": "ZenMux",
        "aiand": "AIand",
        "zoommate": "ZoomMate",

        // Compatibility aliases retained for older local configs and future engine
        // snapshots. They do not replace the exact IDs above.
        "azure-openai": "Azure OpenAI",
        "opencode-go": "OpenCode Go",
        "alibaba-token-plan": "Alibaba Token Plan",
        "qwen-cloud": "Qwen Cloud",
        "droid": "Droid / Factory",
        "vertex": "Vertex AI",
        "command-code": "Command Code",
        "xai": "xAI",
    ]

    static func displayName(for id: String) -> String {
        names[id] ?? id
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    static func documentationURL(for id: String) -> URL {
        let slugs: [String: String] = [
            "azureopenai": "azure-openai",
            "opencodego": "opencode",
            "alibaba": "alibaba-coding-plan",
            "alibabatokenplan": "alibaba-token-plan",
            "qwencloud": "qwen-cloud",
            "commandcode": "command-code",
            "llmproxy": "llm-proxy",
        ]
        let slug = slugs[id] ?? id
        return URL(string: "https://github.com/steipete/CodexBar/blob/main/docs/\(slug).md")!
    }

    static func dashboardURL(for id: String) -> URL? {
        let urls: [String: String] = [
            "codex": "https://chatgpt.com/codex/settings/usage",
            "openai": "https://platform.openai.com/usage",
            "claude": "https://console.anthropic.com/settings/usage",
            "cursor": "https://www.cursor.com/settings",
            "gemini": "https://aistudio.google.com/usage",
            "copilot": "https://github.com/settings/copilot",
            "zai": "https://z.ai/manage-apikey/apikey-list",
            "minimax": "https://platform.minimax.io/user-center/payment/billing",
            "openrouter": "https://openrouter.ai/activity",
            "deepseek": "https://platform.deepseek.com/usage",
            "moonshot": "https://platform.kimi.ai/",
            "mimo": "https://platform.xiaomimimo.com/",
            "mistral": "https://console.mistral.ai/usage",
            "bedrock": "https://console.aws.amazon.com/cost-management/home",
        ]
        return urls[id].flatMap(URL.init(string:))
    }

    static func statusURL(for id: String) -> URL? {
        let urls: [String: String] = [
            "codex": "https://status.openai.com",
            "openai": "https://status.openai.com",
            "claude": "https://status.anthropic.com",
            "cursor": "https://status.cursor.com",
            "gemini": "https://status.cloud.google.com",
            "copilot": "https://www.githubstatus.com",
            "zai": "https://status.z.ai",
            "openrouter": "https://status.openrouter.ai",
            "bedrock": "https://health.aws.amazon.com/health/status",
        ]
        return urls[id].flatMap(URL.init(string:))
    }
}

enum JSONCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatters = ISO8601DateFormatter.compatibleFormatters
            for formatter in formatters {
                if let date = formatter.date(from: value) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
        }
        return decoder
    }()
}

private extension ISO8601DateFormatter {
    static let compatibleFormatters: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let regular = ISO8601DateFormatter()
        regular.formatOptions = [.withInternetDateTime]
        return [fractional, regular]
    }()
}
