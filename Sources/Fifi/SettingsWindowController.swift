import AppKit
import FifiCore

@MainActor
final class SettingsWindowController: NSWindowController, NSTabViewDelegate, NSTextFieldDelegate {
    private enum Pane: String {
        case general
        case storage
        case ignore

        var contentSize: NSSize {
            switch self {
            case .general:
                return NSSize(width: 640, height: 286)
            case .storage:
                return NSSize(width: 640, height: 314)
            case .ignore:
                return NSSize(width: 640, height: 356)
            }
        }
    }

    private enum Metrics {
        static let windowInset: CGFloat = 16
        static let paneInset: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        static let sectionSpacing: CGFloat = 16
        static let columnSpacing: CGFloat = 10
        static let labelWidth: CGFloat = 116
        static let controlWidth: CGFloat = 410
    }

    private let settingsStore: SettingsStore
    private let historyService: HistoryService
    private let ignoreRulesStore: IgnoreRulesStore
    private let monitorReload: () -> Void

    private var didCenter = false
    private var currentPane: Pane = .general
    private var runningApps: [RunningAppChoice] = []

    private let firstModifierPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let secondModifierPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let shortcutKeyField = NSTextField()
    private let shortcutMessageLabel = NSTextField(labelWithString: "")
    private let selectionBehaviorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    private let maxHistoryField = NSTextField()
    private let retentionField = NSTextField()
    private let maxStorageField = NSTextField()
    private let maxHistoryStepper = NSStepper()
    private let retentionStepper = NSStepper()
    private let maxStorageStepper = NSStepper()
    private let usageLabel = NSTextField(labelWithString: "")

    private let ignoredAppsStack = NSStackView()
    private let bundleIDField = NSTextField()
    private let addAppButton = NSButton(title: "Add", target: nil, action: nil)
    private let runningAppsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let ignoreAppsMessageLabel = NSTextField(labelWithString: "")

    private let regexRulesStack = NSStackView()
    private let regexPatternField = NSTextField()
    private let regexLabelField = NSTextField()
    private let addRegexButton = NSButton(title: "Add", target: nil, action: nil)
    private let regexMessageLabel = NSTextField(labelWithString: "")

    init(
        settingsStore: SettingsStore,
        historyService: HistoryService,
        ignoreRulesStore: IgnoreRulesStore,
        monitorReload: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.historyService = historyService
        self.ignoreRulesStore = ignoreRulesStore
        self.monitorReload = monitorReload

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Pane.general.contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeContentView()
        renderAll()
        resize(toContentSize: Pane.general.contentSize)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        renderAll()
        resize(toContentSize: currentPane.contentSize)
        if !didCenter {
            window.center()
            didCenter = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeContentView() -> NSView {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.delegate = self

        tabView.addTabViewItem(tabItem(identifier: Pane.general.rawValue, label: "General", view: makeGeneralView()))
        tabView.addTabViewItem(tabItem(identifier: Pane.storage.rawValue, label: "Storage", view: makeStorageView()))
        tabView.addTabViewItem(tabItem(identifier: Pane.ignore.rawValue, label: "Ignore", view: makeIgnoreView()))

        let contentView = NSView()
        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.windowInset),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.windowInset),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.windowInset),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.windowInset)
        ])
        return contentView
    }

    private func tabItem(identifier: String, label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: identifier)
        item.label = label
        item.view = view
        return item
    }

    private func makeGeneralView() -> NSView {
        configureModifierPopup(firstModifierPopup)
        configureModifierPopup(secondModifierPopup)
        shortcutKeyField.placeholderString = "V"
        shortcutKeyField.alignment = .center
        shortcutKeyField.delegate = self
        shortcutKeyField.target = self
        shortcutKeyField.action = #selector(shortcutChanged)
        shortcutKeyField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        shortcutMessageLabel.font = .systemFont(ofSize: 12)
        shortcutMessageLabel.textColor = .secondaryLabelColor

        selectionBehaviorPopup.addItem(withTitle: "Paste immediately")
        selectionBehaviorPopup.addItem(withTitle: "Copy only")
        selectionBehaviorPopup.target = self
        selectionBehaviorPopup.action = #selector(selectionBehaviorChanged)
        selectionBehaviorPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)

        let shortcutGrid = formGrid([
            [formLabel("Global shortcut"), horizontalStack([firstModifierPopup, secondModifierPopup, shortcutKeyField])],
            [NSView(), shortcutMessageLabel]
        ])
        let behaviorGrid = formGrid([
            [formLabel("On selection"), selectionBehaviorPopup],
            [formLabel("Launch at login"), launchAtLoginCheckbox]
        ])
        return paneView([
            sectionView(title: "Shortcut", body: shortcutGrid),
            sectionView(title: "Behavior", body: behaviorGrid)
        ])
    }

    private func makeStorageView() -> NSView {
        configureIntegerField(maxHistoryField)
        configureIntegerField(retentionField)
        configureIntegerField(maxStorageField)
        configureStepper(maxHistoryStepper, max: 100_000, step: 100, action: #selector(maxHistoryStepperChanged))
        configureStepper(retentionStepper, max: 3_650, step: 1, action: #selector(retentionStepperChanged))
        configureStepper(maxStorageStepper, max: 100_000, step: 64, action: #selector(maxStorageStepperChanged))

        let limitsGrid = formGrid([
            [formLabel("Max history count"), horizontalStack([maxHistoryField, maxHistoryStepper])],
            [formLabel("Retention days"), horizontalStack([retentionField, retentionStepper])],
            [formLabel("Max storage (MB)"), horizontalStack([maxStorageField, maxStorageStepper])],
            [NSView(), secondaryLabel("0 means unlimited.")]
        ])

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshUsageClicked))
        let clearButton = NSButton(title: "Clear History...", target: self, action: #selector(clearHistoryClicked))
        let usageGrid = formGrid([
            [formLabel("Current usage"), usageLabel],
            [formLabel("Actions"), horizontalStack([refreshButton, clearButton])]
        ])
        return paneView([
            sectionView(title: "Limits", body: limitsGrid),
            sectionView(title: "Usage", body: usageGrid)
        ])
    }

    private func makeIgnoreView() -> NSView {
        ignoredAppsStack.orientation = .vertical
        ignoredAppsStack.alignment = .leading
        ignoredAppsStack.spacing = Metrics.rowSpacing
        regexRulesStack.orientation = .vertical
        regexRulesStack.alignment = .leading
        regexRulesStack.spacing = Metrics.rowSpacing

        bundleIDField.placeholderString = "Bundle identifier"
        bundleIDField.delegate = self
        bundleIDField.widthAnchor.constraint(equalToConstant: 206).isActive = true
        addAppButton.target = self
        addAppButton.action = #selector(addAppClicked)
        runningAppsPopup.target = self
        runningAppsPopup.action = #selector(runningAppSelected)
        ignoreAppsMessageLabel.font = .systemFont(ofSize: 12)
        ignoreAppsMessageLabel.textColor = .systemRed

        regexPatternField.placeholderString = "Pattern"
        regexPatternField.delegate = self
        regexPatternField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        regexLabelField.placeholderString = "Label (optional)"
        regexLabelField.delegate = self
        regexLabelField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        addRegexButton.target = self
        addRegexButton.action = #selector(addRegexClicked)
        regexMessageLabel.font = .systemFont(ofSize: 12)
        regexMessageLabel.textColor = .systemRed

        let appsGrid = formGrid([
            [formLabel("Apps"), ignoredAppsStack],
            [formLabel("Add app"), horizontalStack([bundleIDField, addAppButton, runningAppsPopup])],
            [NSView(), ignoreAppsMessageLabel]
        ])
        let regexGrid = formGrid([
            [formLabel("Rules"), regexRulesStack],
            [formLabel("Add rule"), horizontalStack([regexPatternField, regexLabelField, addRegexButton])],
            [NSView(), regexMessageLabel]
        ])
        return paneView([
            sectionView(title: "Ignored Apps", body: appsGrid),
            sectionView(title: "Ignored Text (Regex)", body: regexGrid)
        ])
    }

    private func paneView(_ sections: [NSView]) -> NSView {
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Metrics.paneInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -Metrics.paneInset),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Metrics.paneInset)
        ])
        return view
    }

    private func sectionView(title: String, body: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        let stack = NSStackView(views: [titleLabel, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Metrics.rowSpacing
        return stack
    }

    private func formGrid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = Metrics.rowSpacing
        grid.columnSpacing = Metrics.columnSpacing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = Metrics.labelWidth
        grid.column(at: 1).width = Metrics.controlWidth
        return grid
    }

    private func horizontalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Metrics.rowSpacing
        return stack
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func secondaryLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func configureModifierPopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        for modifier in HotkeyModifier.allCases {
            popup.addItem(withTitle: modifier.title)
            popup.lastItem?.representedObject = modifier.rawValue
        }
        popup.target = self
        popup.action = #selector(shortcutChanged)
        popup.widthAnchor.constraint(equalToConstant: 104).isActive = true
    }

    private func configureIntegerField(_ field: NSTextField) {
        field.alignment = .right
        field.delegate = self
        field.target = self
        field.action = #selector(storageFieldChanged)
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
    }

    private func configureStepper(_ stepper: NSStepper, max: Double, step: Double, action: Selector) {
        stepper.minValue = 0
        stepper.maxValue = max
        stepper.increment = step
        stepper.target = self
        stepper.action = action
    }

    private func renderAll() {
        renderGeneral()
        renderStorage()
        refreshUsage()
        refreshRunningApps()
        reloadIgnoreData()
        updateAddButtonStates()
    }

    private func renderGeneral() {
        let parsed = parseHotkeyShortcut(settingsStore.settings.hotkeyShortcut)
            ?? parseHotkeyShortcut(AppSettings().hotkeyShortcut)
            ?? (.command, .shift, "V")
        firstModifierPopup.selectItem(withTitle: parsed.first.title)
        secondModifierPopup.selectItem(withTitle: parsed.second.title)
        shortcutKeyField.stringValue = parsed.key
        shortcutMessageLabel.stringValue = "Choose two modifier keys, then type one letter or number."
        shortcutMessageLabel.textColor = .secondaryLabelColor
        selectionBehaviorPopup.selectItem(at: settingsStore.settings.selectionBehavior == .paste ? 0 : 1)
        launchAtLoginCheckbox.state = settingsStore.settings.launchAtLogin ? .on : .off
    }

    private func renderStorage() {
        let settings = settingsStore.settings
        maxHistoryField.stringValue = String(settings.maxHistoryCount)
        retentionField.stringValue = String(settings.retentionDays)
        maxStorageField.stringValue = String(settings.maxStorageMB)
        maxHistoryStepper.integerValue = settings.maxHistoryCount
        retentionStepper.integerValue = settings.retentionDays
        maxStorageStepper.integerValue = settings.maxStorageMB
    }

    private func refreshUsage() {
        let usage = historyService.usage()
        usageLabel.stringValue = "\(usage.count) items · \(formatMegabytes(usage.totalBytes))"
    }

    private func reloadIgnoreData() {
        do {
            let ignoredApps = try ignoreRulesStore.ignoredApps()
            ignoredAppsStack.setViews(ignoredApps.isEmpty ? [secondaryLabel("No ignored apps")] : ignoredApps.map(ignoredAppRow), in: .top)
            let regexRules = try ignoreRulesStore.regexRules()
            regexRulesStack.setViews(regexRules.isEmpty ? [secondaryLabel("No rules")] : regexRules.map(regexRuleRow), in: .top)
            ignoreAppsMessageLabel.stringValue = ""
            regexMessageLabel.stringValue = ""
        } catch {
            ignoreAppsMessageLabel.stringValue = "Couldn’t load ignore rules."
            NSLog("Failed to load ignore rules: \(String(describing: error))")
        }
    }

    private func ignoredAppRow(_ app: IgnoredApp) -> NSView {
        let title = NSTextField(labelWithString: app.appName?.isEmpty == false ? app.appName! : app.bundleID)
        let subtitle = secondaryLabel(app.bundleID)
        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        let button = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Remove") ?? NSImage(), target: self, action: #selector(removeIgnoredAppClicked(_:)))
        button.isBordered = false
        button.identifier = NSUserInterfaceItemIdentifier(app.bundleID)
        let row = horizontalStack([textStack, button])
        row.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.controlWidth).isActive = true
        return row
    }

    private func regexRuleRow(_ rule: IgnoreRegexRule) -> NSView {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(regexRuleEnabledChanged(_:)))
        checkbox.state = rule.enabled ? .on : .off
        checkbox.tag = Int(rule.id)
        let title = NSTextField(labelWithString: rule.pattern)
        title.lineBreakMode = .byTruncatingTail
        title.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        var textViews: [NSView] = [title]
        if let label = rule.label, !label.isEmpty {
            textViews.append(secondaryLabel(label))
        }
        let textStack = NSStackView(views: textViews)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        let button = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Remove") ?? NSImage(), target: self, action: #selector(removeRegexRuleClicked(_:)))
        button.isBordered = false
        button.tag = Int(rule.id)
        return horizontalStack([checkbox, textStack, button])
    }

    private func refreshRunningApps() {
        var seen = Set<String>()
        runningApps = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else {
                return nil
            }
            return RunningAppChoice(name: app.localizedName ?? bundleID, bundleID: bundleID)
        }
        .filter { seen.insert($0.bundleID).inserted }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        runningAppsPopup.removeAllItems()
        runningAppsPopup.addItem(withTitle: "Running Apps")
        runningAppsPopup.item(at: 0)?.representedObject = ""
        for app in runningApps {
            runningAppsPopup.addItem(withTitle: app.name)
            runningAppsPopup.lastItem?.representedObject = app.bundleID
        }
        runningAppsPopup.selectItem(at: 0)
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let identifier = tabViewItem?.identifier as? String,
              let pane = Pane(rawValue: identifier) else {
            return
        }
        currentPane = pane
        resize(toContentSize: pane.contentSize)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let object = notification.object as? NSTextField else { return }
        switch object {
        case shortcutKeyField:
            shortcutChanged()
        case maxHistoryField, retentionField, maxStorageField:
            storageFieldChanged()
        default:
            updateAddButtonStates()
        }
    }

    @objc private func shortcutChanged() {
        let normalizedKey = normalizeHotkeyKey(shortcutKeyField.stringValue)
        if shortcutKeyField.stringValue != normalizedKey {
            shortcutKeyField.stringValue = normalizedKey
        }
        let first = selectedModifier(firstModifierPopup)
        let second = selectedModifier(secondModifierPopup)
        guard first != second else {
            setShortcutMessage("Choose two different modifier keys.", isError: true)
            return
        }
        guard !normalizedKey.isEmpty else {
            setShortcutMessage("Type one letter or number for the shortcut key.", isError: true)
            return
        }
        let shortcut = "\(first.token)+\(second.token)+\(normalizedKey.lowercased())"
        guard HotKeyCenter.isShortcutSupported(shortcut) else {
            setShortcutMessage("Unsupported shortcut.", isError: true)
            return
        }
        setShortcutMessage("Choose two modifier keys, then type one letter or number.", isError: false)
        settingsStore.update { settings in
            settings.hotkeyShortcut = shortcut
        }
    }

    @objc private func selectionBehaviorChanged() {
        settingsStore.update { settings in
            settings.selectionBehavior = selectionBehaviorPopup.indexOfSelectedItem == 0 ? .paste : .copy
        }
    }

    @objc private func launchAtLoginChanged() {
        settingsStore.update { settings in
            settings.launchAtLogin = launchAtLoginCheckbox.state == .on
        }
    }

    @objc private func storageFieldChanged() {
        let maxHistoryCount = clampedInteger(maxHistoryField.stringValue)
        let retentionDays = clampedInteger(retentionField.stringValue)
        let maxStorageMB = clampedInteger(maxStorageField.stringValue)
        maxHistoryStepper.integerValue = maxHistoryCount
        retentionStepper.integerValue = retentionDays
        maxStorageStepper.integerValue = maxStorageMB
        settingsStore.update { settings in
            settings.maxHistoryCount = maxHistoryCount
            settings.retentionDays = retentionDays
            settings.maxStorageMB = maxStorageMB
        }
    }

    @objc private func maxHistoryStepperChanged() {
        maxHistoryField.stringValue = String(maxHistoryStepper.integerValue)
        storageFieldChanged()
    }

    @objc private func retentionStepperChanged() {
        retentionField.stringValue = String(retentionStepper.integerValue)
        storageFieldChanged()
    }

    @objc private func maxStorageStepperChanged() {
        maxStorageField.stringValue = String(maxStorageStepper.integerValue)
        storageFieldChanged()
    }

    @objc private func refreshUsageClicked() {
        refreshUsage()
    }

    @objc private func clearHistoryClicked() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Pinned items will be kept. This cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            historyService.clearAll(keepPinned: true)
            refreshUsage()
        }
    }

    @objc private func addAppClicked() {
        addIgnoredApp(bundleID: bundleIDField.stringValue, appName: nil)
    }

    @objc private func runningAppSelected() {
        let bundleID = runningAppsPopup.selectedItem?.representedObject as? String ?? ""
        guard !bundleID.isEmpty else { return }
        let app = runningApps.first { $0.bundleID == bundleID }
        addIgnoredApp(bundleID: bundleID, appName: app?.name)
        runningAppsPopup.selectItem(at: 0)
    }

    @objc private func removeIgnoredAppClicked(_ sender: NSButton) {
        guard let bundleID = sender.identifier?.rawValue else { return }
        do {
            try ignoreRulesStore.removeIgnoredApp(bundleID: bundleID)
            reloadIgnoreData()
            monitorReload()
        } catch {
            ignoreAppsMessageLabel.stringValue = "Couldn’t remove app."
            NSLog("Failed to remove ignored app \(bundleID): \(String(describing: error))")
        }
    }

    @objc private func addRegexClicked() {
        let pattern = regexPatternField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = regexLabelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        do {
            _ = try NSRegularExpression(pattern: pattern)
            _ = try ignoreRulesStore.addRegexRule(pattern: pattern, label: label.isEmpty ? nil : label)
            regexPatternField.stringValue = ""
            regexLabelField.stringValue = ""
            updateAddButtonStates()
            reloadIgnoreData()
            monitorReload()
        } catch {
            regexMessageLabel.stringValue = "Invalid regex: \(error.localizedDescription)"
            NSLog("Failed to add regex rule: \(String(describing: error))")
        }
    }

    @objc private func regexRuleEnabledChanged(_ sender: NSButton) {
        let id = Int64(sender.tag)
        do {
            try ignoreRulesStore.setRegexRule(id: id, enabled: sender.state == .on)
            reloadIgnoreData()
            monitorReload()
        } catch {
            regexMessageLabel.stringValue = "Couldn’t update rule."
            NSLog("Failed to update regex rule \(id): \(String(describing: error))")
        }
    }

    @objc private func removeRegexRuleClicked(_ sender: NSButton) {
        let id = Int64(sender.tag)
        do {
            try ignoreRulesStore.removeRegexRule(id: id)
            reloadIgnoreData()
            monitorReload()
        } catch {
            regexMessageLabel.stringValue = "Couldn’t remove rule."
            NSLog("Failed to remove regex rule \(id): \(String(describing: error))")
        }
    }

    private func addIgnoredApp(bundleID: String, appName: String?) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try ignoreRulesStore.addIgnoredApp(bundleID: trimmed, appName: appName)
            bundleIDField.stringValue = ""
            updateAddButtonStates()
            reloadIgnoreData()
            monitorReload()
        } catch {
            ignoreAppsMessageLabel.stringValue = "Couldn’t add app."
            NSLog("Failed to add ignored app \(trimmed): \(String(describing: error))")
        }
    }

    private func setShortcutMessage(_ text: String, isError: Bool) {
        shortcutMessageLabel.stringValue = text
        shortcutMessageLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func updateAddButtonStates() {
        addAppButton.isEnabled = !bundleIDField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        addRegexButton.isEnabled = !regexPatternField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func selectedModifier(_ popup: NSPopUpButton) -> HotkeyModifier {
        guard let rawValue = popup.selectedItem?.representedObject as? String,
              let modifier = HotkeyModifier(rawValue: rawValue) else {
            return .command
        }
        return modifier
    }

    private func parseHotkeyShortcut(_ shortcut: String) -> (first: HotkeyModifier, second: HotkeyModifier, key: String)? {
        let tokens = shortcut
            .replacingOccurrences(of: "⌘", with: "cmd+")
            .replacingOccurrences(of: "⇧", with: "shift+")
            .replacingOccurrences(of: "⌥", with: "option+")
            .replacingOccurrences(of: "⌃", with: "control+")
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard tokens.count >= 3 else { return nil }
        let modifiers = tokens.dropLast().compactMap(HotkeyModifier.init(token:))
        let uniqueModifiers = modifiers.reduce(into: [HotkeyModifier]()) { result, modifier in
            if !result.contains(modifier) {
                result.append(modifier)
            }
        }
        let key = normalizeHotkeyKey(String(tokens.last ?? ""))
        guard uniqueModifiers.count >= 2, !key.isEmpty else { return nil }
        return (uniqueModifiers[0], uniqueModifiers[1], key)
    }

    private func normalizeHotkeyKey(_ rawValue: String) -> String {
        let allowedCharacters = rawValue.uppercased().filter { $0.isLetter || $0.isNumber }
        return String(allowedCharacters.prefix(1))
    }

    private func formatMegabytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.1f MB", mb)
    }

    private func clampedInteger(_ rawValue: String) -> Int {
        let digits = rawValue.filter { $0.isNumber }
        return max(0, Int(digits) ?? 0)
    }

    private func resize(toContentSize size: NSSize) {
        guard let window else { return }
        window.contentMinSize = size
        window.contentMaxSize = size
        let frame = window.frame
        let contentRect = window.contentRect(forFrameRect: frame)
        guard abs(contentRect.width - size.width) > 0.5 || abs(contentRect.height - size.height) > 0.5 else {
            return
        }
        var nextFrame = window.frameRect(forContentRect: NSRect(origin: contentRect.origin, size: size))
        nextFrame.origin.y = frame.maxY - nextFrame.height
        window.setFrame(nextFrame, display: true, animate: false)
    }
}

private enum HotkeyModifier: String, CaseIterable {
    case command
    case shift
    case option
    case control

    var title: String {
        switch self {
        case .command: return "Command"
        case .shift: return "Shift"
        case .option: return "Option"
        case .control: return "Control"
        }
    }

    var token: String {
        switch self {
        case .command: return "cmd"
        case .shift: return "shift"
        case .option: return "option"
        case .control: return "control"
        }
    }

    init?(token: String) {
        switch token {
        case "cmd", "command":
            self = .command
        case "shift":
            self = .shift
        case "option", "alt":
            self = .option
        case "ctrl", "control":
            self = .control
        default:
            return nil
        }
    }
}

private struct RunningAppChoice {
    let name: String
    let bundleID: String
}
