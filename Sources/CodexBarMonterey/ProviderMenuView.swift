@preconcurrency import AppKit

final class ProviderMenuView: NSView {
    private static let preferredWidth: CGFloat = 310

    init(snapshot: ProviderSnapshot) {
        let width = Self.preferredWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 80))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.providerColor(id: snapshot.provider).cgColor
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])

        let title = NSTextField(labelWithString: snapshot.displayName)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let source = NSTextField(labelWithString: snapshot.source.map { "· \($0)" } ?? "")
        source.font = .systemFont(ofSize: 11)
        source.textColor = .secondaryLabelColor
        header.addArrangedSubview(dot)
        header.addArrangedSubview(title)
        header.addArrangedSubview(source)
        stack.addArrangedSubview(header)

        if let error = Self.userFacingError(for: snapshot) {
            let field = NSTextField(wrappingLabelWithString: error)
            field.font = .systemFont(ofSize: 11)
            field.textColor = .systemRed
            field.maximumNumberOfLines = 2
            stack.addArrangedSubview(field)
        } else {
            let windows = [snapshot.usage?.primary, snapshot.usage?.secondary, snapshot.usage?.tertiary].compactMap { $0 }
            for window in windows.prefix(3) {
                stack.addArrangedSubview(Self.makeWindowRow(window: window, provider: snapshot.provider))
            }
            if windows.isEmpty {
                let detail = snapshot.credits?.remaining.map { "Credits remaining: \(Self.number($0))" }
                    ?? snapshot.plan.map { "Plan: \($0)" }
                    ?? "No percentage quota returned"
                let field = NSTextField(labelWithString: detail)
                field.font = .systemFont(ofSize: 11)
                field.textColor = .secondaryLabelColor
                stack.addArrangedSubview(field)
            }
        }

        layoutSubtreeIfNeeded()
        let measured = stack.fittingSize.height
        frame.size.height = max(56, measured)
        heightAnchor.constraint(equalToConstant: frame.size.height).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    private static func userFacingError(for snapshot: ProviderSnapshot) -> String? {
        guard let message = snapshot.error?.message else { return nil }
        if snapshot.provider == "zai",
           message.localizedCaseInsensitiveContains("No available fetch strategy")
        {
            return "z.ai requires an API key. Open Settings → Providers, click the z.ai name, then choose Set API key…"
        }
        return message
    }

    private static func makeWindowRow(window: RateWindow, provider: String) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 2

        let top = NSStackView()
        top.orientation = .horizontal
        top.distribution = .fill
        let used = window.usedPercent ?? 0
        let label = NSTextField(labelWithString: window.displayLabel)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        let value = NSTextField(labelWithString: String(format: "%.0f%% used", used))
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.textColor = .secondaryLabelColor
        top.addArrangedSubview(label)
        top.addArrangedSubview(NSView())
        top.addArrangedSubview(value)
        container.addArrangedSubview(top)

        let bar = QuotaBarView()
        bar.progress = used
        bar.fillColor = NSColor.providerColor(id: provider)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 5).isActive = true
        container.addArrangedSubview(bar)

        if let reset = window.resetText {
            let resetField = NSTextField(labelWithString: reset)
            resetField.font = .systemFont(ofSize: 10)
            resetField.textColor = .tertiaryLabelColor
            container.addArrangedSubview(resetField)
        }
        return container
    }

    private static func number(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
