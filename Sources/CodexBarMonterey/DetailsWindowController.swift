@preconcurrency import AppKit

@MainActor
final class DetailsWindowController: NSWindowController {
    private enum Mode {
        case usage
        case cost
    }

    private let client: CLIClient
    private let scrollView: NSScrollView
    private let textView: NSTextView
    private var requestedProvider: String?
    private var mode: Mode = .usage

    init(client: CLIClient) {
        self.client = client

        // Let AppKit create a correctly wired scroll view/text view pair. A bare
        // NSTextView starts with a zero-sized text container when assigned as an
        // NSScrollView documentView, which produced the completely white details
        // window seen on Monterey.
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            preconditionFailure("NSTextView.scrollableTextView() did not return a text view")
        }
        self.scrollView = scrollView
        self.textView = textView

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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reload()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        scrollView.frame = content.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        content.addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindPanel = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude)
    }

    private func reload() {
        textView.string = mode == .usage
            ? "Refreshing upstream provider details…"
            : "Scanning upstream provider cost data…"
        textView.scrollToBeginningOfDocument(nil)

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
                textView.string = text.isEmpty ? "The provider returned no detail text." : text
            } catch {
                textView.string = error.localizedDescription
            }
            textView.scrollToBeginningOfDocument(nil)
        }
    }
}
