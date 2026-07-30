@preconcurrency import AppKit

@MainActor
final class DetailsWindowController: NSWindowController {
    private enum Mode {
        case usage
        case cost
    }

    private let client: CLIClient
    private let textView = NSTextView()
    private var requestedProvider: String?
    private var mode: Mode = .usage

    init(client: CLIClient) {
        self.client = client
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "CodexBar Provider Details"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { nil }

    func showUsage(provider: String?, displayName: String?) {
        mode = .usage
        requestedProvider = provider
        window?.title = displayName.map { "\($0) — Full Usage Details" } ?? "All Enabled Providers — Full Usage Details"
        presentAndReload()
    }

    func showCost(provider: String?, displayName: String?) {
        mode = .cost
        requestedProvider = provider
        window?.title = displayName.map { "\($0) — Cost Details" } ?? "All Supported Providers — Cost Details"
        presentAndReload()
    }

    private func presentAndReload() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let scroll = NSScrollView(frame: content.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        content.addSubview(scroll)
    }

    private func reload() {
        textView.string = mode == .usage ? "Refreshing upstream provider details…" : "Scanning upstream provider cost data…"
        let provider = requestedProvider
        let requestedMode = mode
        Task {
            do {
                let text: String
                switch requestedMode {
                case .usage:
                    text = try await client.detailedText(provider: provider)
                case .cost:
                    text = try await client.costText(provider: provider)
                }
                textView.string = text
            } catch {
                textView.string = error.localizedDescription
            }
        }
    }
}
