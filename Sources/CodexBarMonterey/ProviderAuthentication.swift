import Foundation

enum ProviderCredentialStorage: String, Hashable {
    case apiKey
    case tokenAccount
    case manualCookie
    case providerFields
    case external
}

struct ProviderAuthenticationProfile: Hashable {
    let providerID: String
    let title: String
    let guidance: String
    let storage: ProviderCredentialStorage
    let secretLabel: String
    let secretPlaceholder: String
    let accountLabelVisible: Bool
    let enterpriseHostLabel: String?
    let enterpriseHostRequired: Bool
    let workspaceLabel: String?
    let workspaceRequired: Bool
    let regionLabel: String?
    let regionPlaceholder: String?
    let probeSource: String?
    let supportsBrowserTools: Bool

    var requiresSecret: Bool {
        storage == .apiKey || storage == .tokenAccount || storage == .manualCookie
    }

    var canSaveConfiguration: Bool {
        storage != .external
    }

    var methodTitle: String {
        switch storage {
        case .apiKey: return "API key"
        case .tokenAccount: return "Multiple token accounts"
        case .manualCookie: return "Browser session or cookie"
        case .providerFields: return "Provider fields"
        case .external: return title
        }
    }

    var methodSymbol: String {
        switch storage {
        case .apiKey, .tokenAccount: return "key.fill"
        case .manualCookie: return "globe"
        case .providerFields: return "slider.horizontal.3"
        case .external: return "person.badge.key"
        }
    }
}

enum ProviderAuthenticationCatalog {
    static let stableProviderIDs: [String] = [
        "codex", "openai", "azureopenai", "claude", "clinepass", "cursor",
        "opencode", "opencodego", "alibaba", "alibabatokenplan", "qwencloud",
        "factory", "gemini", "antigravity", "copilot", "devin", "zai",
        "minimax", "manus", "kimi", "kilo", "kiro", "vertexai", "augment",
        "jetbrains", "moonshot", "amp", "t3chat", "ollama", "synthetic",
        "warp", "openrouter", "elevenlabs", "windsurf", "zed", "perplexity",
        "mimo", "doubao", "sakana", "abacus", "mistral", "deepseek",
        "deepinfra", "codebuff", "crof", "venice", "commandcode", "qoder",
        "stepfun", "bedrock", "grok", "groq", "llmproxy", "litellm",
        "deepgram", "poe", "chutes", "neuralwatt", "clawrouter", "longcat",
        "sub2api", "wayfinder", "zenmux", "aiand", "zoommate", "xai",
    ]

    private static func api(
        _ id: String,
        _ guidance: String,
        secretLabel: String = "API key",
        placeholder: String = "Paste API key or token",
        host: String? = nil,
        hostRequired: Bool = false,
        workspace: String? = nil,
        workspaceRequired: Bool = false,
        region: String? = nil,
        regionPlaceholder: String? = nil,
        browser: Bool = false
    ) -> ProviderAuthenticationProfile {
        ProviderAuthenticationProfile(
            providerID: id,
            title: "API authentication",
            guidance: guidance,
            storage: .apiKey,
            secretLabel: secretLabel,
            secretPlaceholder: placeholder,
            accountLabelVisible: false,
            enterpriseHostLabel: host,
            enterpriseHostRequired: hostRequired,
            workspaceLabel: workspace,
            workspaceRequired: workspaceRequired,
            regionLabel: region,
            regionPlaceholder: regionPlaceholder,
            probeSource: "api",
            supportsBrowserTools: browser)
    }

    private static func tokenAccount(
        _ id: String,
        _ guidance: String,
        placeholder: String = "Paste API key"
    ) -> ProviderAuthenticationProfile {
        ProviderAuthenticationProfile(
            providerID: id,
            title: "API token account",
            guidance: guidance,
            storage: .tokenAccount,
            secretLabel: "API key",
            secretPlaceholder: placeholder,
            accountLabelVisible: true,
            enterpriseHostLabel: nil,
            enterpriseHostRequired: false,
            workspaceLabel: nil,
            workspaceRequired: false,
            regionLabel: nil,
            regionPlaceholder: nil,
            probeSource: "api",
            supportsBrowserTools: id == "deepseek")
    }

    private static func cookie(
        _ id: String,
        _ guidance: String,
        secretLabel: String = "Cookie or session token",
        placeholder: String = "Paste Cookie header or session token"
    ) -> ProviderAuthenticationProfile {
        ProviderAuthenticationProfile(
            providerID: id,
            title: "Browser or session authentication",
            guidance: guidance,
            storage: .manualCookie,
            secretLabel: secretLabel,
            secretPlaceholder: placeholder,
            accountLabelVisible: false,
            enterpriseHostLabel: nil,
            enterpriseHostRequired: false,
            workspaceLabel: nil,
            workspaceRequired: false,
            regionLabel: nil,
            regionPlaceholder: nil,
            probeSource: "web",
            supportsBrowserTools: true)
    }

    private static func fields(
        _ id: String,
        _ guidance: String,
        host: String? = nil,
        hostRequired: Bool = false,
        workspace: String? = nil,
        workspaceRequired: Bool = false,
        region: String? = nil,
        regionPlaceholder: String? = nil
    ) -> ProviderAuthenticationProfile {
        ProviderAuthenticationProfile(
            providerID: id,
            title: "Provider configuration",
            guidance: guidance,
            storage: .providerFields,
            secretLabel: "",
            secretPlaceholder: "",
            accountLabelVisible: false,
            enterpriseHostLabel: host,
            enterpriseHostRequired: hostRequired,
            workspaceLabel: workspace,
            workspaceRequired: workspaceRequired,
            regionLabel: region,
            regionPlaceholder: regionPlaceholder,
            probeSource: nil,
            supportsBrowserTools: false)
    }

    private static func external(
        _ id: String,
        _ title: String,
        _ guidance: String,
        browser: Bool = false
    ) -> ProviderAuthenticationProfile {
        ProviderAuthenticationProfile(
            providerID: id,
            title: title,
            guidance: guidance,
            storage: .external,
            secretLabel: "",
            secretPlaceholder: "",
            accountLabelVisible: false,
            enterpriseHostLabel: nil,
            enterpriseHostRequired: false,
            workspaceLabel: nil,
            workspaceRequired: false,
            regionLabel: nil,
            regionPlaceholder: nil,
            probeSource: nil,
            supportsBrowserTools: browser)
    }

    static let profiles: [String: ProviderAuthenticationProfile] = {
        let rows: [ProviderAuthenticationProfile] = [
            external("codex", "OAuth / Codex CLI", "Uses ~/.codex OAuth credentials or the installed Codex CLI. OpenAI browser extras are optional.", browser: true),
            api("openai", "Requires an OpenAI Admin key for organization usage. A normal API key only exposes limited balance data.", workspace: "OpenAI project ID (optional)"),
            api("azureopenai", "Requires an Azure OpenAI key, endpoint, and deployment name.", host: "Azure endpoint", hostRequired: true, workspace: "Deployment name", workspaceRequired: true),
            api("claude", "API mode requires an Anthropic Admin key. OAuth, Claude CLI, and browser-session modes remain available.", browser: true),
            external("clinepass", "Provider-managed authentication", "Uses the ClinePass credentials or provider-specific login described in the upstream documentation."),
            cookie("cursor", "Uses a signed-in Cursor browser session. Paste a Cookie header only when automatic browser import is unavailable."),
            cookie("opencode", "Uses the OpenCode web dashboard session."),
            fields("opencodego", "Uses the OpenCode Go web/local source. A workspace ID is optional.", workspace: "Workspace ID (optional)"),
            api("alibaba", "Supports an Alibaba Coding Plan API key, with browser cookies as an alternative.", region: "Region (optional)", regionPlaceholder: "international or china", browser: true),
            cookie("alibabatokenplan", "Uses Bailian browser or manual cookies."),
            cookie("qwencloud", "Uses Qwen Cloud browser or manual session cookies."),
            cookie("factory", "Uses Factory cookies or a pasted Bearer token.", secretLabel: "Cookie or Bearer token"),
            external("gemini", "Gemini CLI OAuth", "Uses Gemini CLI OAuth credentials; no standalone API key should be saved here."),
            external("antigravity", "Local probe", "Uses the local Antigravity language server and needs no external credential."),
            api("copilot", "Accepts a GitHub/Copilot API token; GitHub device-flow login is also supported.", secretLabel: "GitHub token"),
            cookie("devin", "Uses Chrome localStorage or a manual Bearer token.", secretLabel: "Bearer token"),
            api("zai", "Uses a z.ai API token. Region and optional workspace/project scoping are preserved.", workspace: "Workspace/project ID (optional)", region: "Region (optional)", regionPlaceholder: "global or bigmodel-cn"),
            api("minimax", "Uses a MiniMax Coding Plan API token, or a browser session.", region: "Region (optional)", regionPlaceholder: "global or china", browser: true),
            cookie("manus", "Uses a Manus session_id cookie."),
            cookie("kimi", "Uses the kimi-auth JWT or a full Cookie header.", secretLabel: "Kimi auth token"),
            api("kilo", "Uses a Kilo API token; the Kilo CLI login remains an automatic fallback."),
            external("kiro", "Kiro CLI", "Requires kiro-cli installed and signed in with AWS Builder ID."),
            external("vertexai", "Google Cloud OAuth", "Uses gcloud Application Default Credentials and Cloud Monitoring access."),
            external("augment", "Augment CLI / browser", "Uses the auggie CLI first and browser cookies as a fallback.", browser: true),
            external("jetbrains", "Local IDE configuration", "Reads the local JetBrains AI quota XML file; no key is required."),
            api("moonshot", "Uses a Moonshot/Kimi API key. Select the matching international or China region.", region: "Region (optional)", regionPlaceholder: "international or china"),
            cookie("amp", "Uses the signed-in Amp settings-page browser session."),
            cookie("t3chat", "Uses T3 Chat browser cookies."),
            api("ollama", "An API key validates Ollama Cloud access; browser cookies can expose Cloud quota windows.", browser: true),
            api("synthetic", "Uses a Synthetic API key."),
            api("warp", "Uses a Warp API token."),
            api("openrouter", "Uses an OpenRouter API key."),
            api("elevenlabs", "Uses an ElevenLabs API key."),
            external("windsurf", "Browser / local cache", "Uses browser localStorage or the local Windsurf SQLite cache.", browser: true),
            external("zed", "Zed Keychain session", "Uses the local Zed editor Keychain session."),
            cookie("perplexity", "Uses a Perplexity session token or browser Cookie header."),
            cookie("mimo", "Uses Xiaomi MiMo browser cookies."),
            api("doubao", "Uses a Volcengine Ark / Doubao API key."),
            cookie("sakana", "Uses a manual Sakana Cookie header."),
            cookie("abacus", "Uses Abacus AI browser cookies."),
            cookie("mistral", "Uses Mistral Console Ory session cookies."),
            tokenAccount("deepseek", "DeepSeek keys are stored as tokenAccounts, matching upstream CodexBar. The generic config set-api-key command is intentionally not used."),
            api("deepinfra", "Uses a DeepInfra API key."),
            api("codebuff", "Uses a Codebuff API token; codebuff login credentials remain a fallback."),
            api("crof", "Uses a Crof API key."),
            tokenAccount("venice", "Venice keys are stored as tokenAccounts, matching upstream CodexBar."),
            cookie("commandcode", "Uses Command Code browser cookies."),
            cookie("qoder", "Uses Qoder browser or manual cookies."),
            cookie("stepfun", "Uses a manual Oasis token. Username/password login is handled by the provider flow.", secretLabel: "Oasis token"),
            external("bedrock", "AWS credentials / profile", "Uses AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, optional session token, or a named AWS profile."),
            external("grok", "Grok CLI / browser", "Uses grok login and the Grok CLI billing RPC, with browser-session fallback.", browser: true),
            api("groq", "Uses a GroqCloud API key."),
            api("llmproxy", "Requires an API key and the proxy base URL.", host: "Proxy base URL", hostRequired: true),
            api("litellm", "Requires a LiteLLM virtual key and proxy base URL.", host: "LiteLLM base URL", hostRequired: true),
            api("deepgram", "Uses a Deepgram API key. A project ID is optional.", workspace: "Project ID (optional)"),
            api("poe", "Uses a Poe API key."),
            api("chutes", "Uses a Chutes API key."),
            api("neuralwatt", "Uses a Neuralwatt API key."),
            api("clawrouter", "Uses a ClawRouter API key. The hosted service is the default; a custom base URL is optional.", host: "Custom base URL (optional)"),
            api("longcat", "Uses a LongCat API key."),
            api("sub2api", "Requires a gateway key and the self-hosted base URL.", host: "Gateway base URL", hostRequired: true),
            fields("wayfinder", "Uses a local Wayfinder router gateway.", host: "Router base URL", hostRequired: true),
            api("zenmux", "Uses a ZenMux Management API key."),
            api("aiand", "Uses an AIand API key."),
            cookie("zoommate", "Uses ZoomMate browser cookies or a captured manual session."),
            api("xai", "Requires an xAI Management API key and team ID; inference keys are not accepted.", secretLabel: "Management API key", workspace: "Team ID", workspaceRequired: true),
        ]
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.providerID, $0) })
    }()

    static func profile(for providerID: String) -> ProviderAuthenticationProfile {
        if let profile = profiles[providerID] {
            return profile
        }
        return external(
            providerID,
            "Provider-managed authentication",
            "This provider is newer than the bundled authentication catalog. Use its upstream documentation and config file until the catalog is updated.")
    }

    static var uncoveredStableProviderIDs: [String] {
        stableProviderIDs.filter { profiles[$0] == nil }
    }
}

struct ProviderCredentialInput: Hashable {
    let secret: String
    let accountLabel: String
    let enterpriseHost: String
    let workspaceID: String
    let region: String
}

struct CredentialSaveReceipt: Hashable {
    let configURL: URL
}
