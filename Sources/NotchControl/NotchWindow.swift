import AppKit
import Combine
import SwiftUI

enum NotchMetrics {
    static let expandedSize = CGSize(width: 740, height: 380)
    static let wingWidth: CGFloat = 150
    static let virtualNotch = CGSize(width: 0, height: 30)
}

enum NotchTab: String, CaseIterable, Identifiable {
    case agents = "Agents", reminders = "Tasks", focus = "Focus", notes = "Notes", shelf = "Shelf",
         music = "Music", clipboard = "Clipboard", calendar = "Calendar"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .agents: return "terminal"
        case .music: return "music.note"
        case .clipboard: return "doc.on.clipboard"
        case .reminders: return "checklist"
        case .focus: return "timer"
        case .calendar: return "calendar"
        case .notes: return "note.text"
        case .shelf: return "tray.full"
        }
    }
}

final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var selectedTab: NotchTab = .agents
    @Published var notchSize = NotchMetrics.virtualNotch
    @Published var hasPhysicalNotch = false

    private var collapseWork: DispatchWorkItem?
    private var lastHoverLogged: Bool?

    var collapsedSize: CGSize {
        CGSize(width: notchSize.width + NotchMetrics.wingWidth * 2, height: notchSize.height)
    }

    func setHover(_ hovering: Bool) {
        if hovering != lastHoverLogged { DebugLog.log("hover=\(hovering) expanded=\(isExpanded)"); lastHoverLogged = hovering }
        if hovering {
            collapseWork?.cancel()
            collapseWork = nil
            if !isExpanded { isExpanded = true }
        } else if isExpanded, collapseWork == nil {
            scheduleCollapse(after: 0.5)
        }
    }

    /// Open the panel programmatically, e.g. when an agent needs approval.
    func expand(tab: NotchTab, autoCollapseAfter seconds: Double?) {
        collapseWork?.cancel()
        selectedTab = tab
        isExpanded = true
        if let seconds { scheduleCollapse(after: seconds) }
    }

    func collapse() {
        collapseWork?.cancel()
        isExpanded = false
    }

    private func scheduleCollapse(after seconds: Double) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collapseWork = nil
            self?.isExpanded = false
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the borderless panel pinned to the top centre of the screen, over the notch.
final class NotchWindowController {
    let panel: NotchPanel
    let vm: NotchViewModel
    private var screen: NSScreen?
    private var cancellables = Set<AnyCancellable>()

    init(vm: NotchViewModel, content: AnyView) {
        self.vm = vm
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        let hosting = HoverHostingView(rootView: content)
        hosting.sizingOptions = []            // never let SwiftUI's ideal size fight the window frame
        hosting.autoresizingMask = [.width, .height]
        hosting.onHoverChange = { [weak self] inside in
            guard let self else { return }
            if inside && !self.vm.isExpanded { return } // collapsed: only the pill area counts (global monitor)
            self.vm.setHover(inside)
        }
        panel.contentView = hosting
        installMouseMonitors()

        detectScreen()
        layout(expanded: false)
        panel.orderFrontRegardless()

        // @Published emits in willSet, before the new value is stored. Resizing the window
        // synchronously there forces SwiftUI to evaluate its body with the stale value, so
        // defer the layout to the next run-loop pass.
        vm.$isExpanded
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded in self?.layout(expanded: expanded) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.detectScreen()
                self.layout(expanded: self.vm.isExpanded)
            }
            .store(in: &cancellables)
    }

    // Fallback for hover: tracking areas can miss events in a non-activating panel that
    // sits over the menu bar, so also watch the global mouse position.
    private var monitors: [Any] = []
    private var mouseInside = false

    private func installMouseMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.checkMouse() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in handler(e); return e }) {
            monitors.append(local)
        }
    }

    private func checkMouse() {
        let target = vm.isExpanded ? panel.frame : pillRect.insetBy(dx: -4, dy: -2)
        let inside = target.contains(NSEvent.mouseLocation)
        guard inside != mouseInside else { return }
        mouseInside = inside
        vm.setHover(inside)
    }

    /// Debug: render the panel's content to a PNG and log the view sizes.
    func snapshot(to url: URL) {
        guard let view = panel.contentView else { return }
        DebugLog.log("snapshot window=\(panel.frame) contentView=\(view.frame) subviews=\(view.subviews.map { $0.frame })")
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }

    private func detectScreen() {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        screen = notched ?? NSScreen.main ?? NSScreen.screens.first
        if let s = notched {
            let left = s.auxiliaryTopLeftArea?.width ?? 0
            let right = s.auxiliaryTopRightArea?.width ?? 0
            let width = max(120, s.frame.width - left - right)
            vm.notchSize = CGSize(width: width, height: s.safeAreaInsets.top)
            vm.hasPhysicalNotch = true
        } else {
            vm.notchSize = NotchMetrics.virtualNotch
            vm.hasPhysicalNotch = false
        }
    }

    /// The panel always has the expanded size so the content can animate freely; while
    /// collapsed it ignores mouse events and the global monitor watches the pill area instead.
    private func layout(expanded: Bool) {
        guard let s = screen else { return }
        let size = NotchMetrics.expandedSize
        let frame = NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.ignoresMouseEvents = !expanded
        DebugLog.log("layout expanded=\(expanded) frame=\(frame) screen=\(s.localizedName) notch=\(vm.hasPhysicalNotch)")
    }

    /// Screen rect (bottom-left origin) of the visible pill while collapsed.
    private var pillRect: NSRect {
        let size = vm.collapsedSize
        return NSRect(x: panel.frame.midX - size.width / 2, y: panel.frame.maxY - size.height,
                      width: size.width, height: size.height)
    }
}

/// NSHostingView that reports mouse enter/exit with an always-active tracking area.
final class HoverHostingView: NSHostingView<AnyView> {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        DebugLog.log("mouseDown at \(event.locationInWindow)")
        super.mouseDown(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}
