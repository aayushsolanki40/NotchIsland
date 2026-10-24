import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }
    // Must be able to become key or SwiftUI buttons ignore clicks; the panel
    // is non-activating, so the frontmost app still keeps focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the transparent panel pinned to the top-center of the screen and
/// routes mouse events only when the cursor is over the island itself.
final class IslandWindowController {
    static let canvas = CGSize(width: 760, height: 320)

    private let model: IslandModel
    private let panel: IslandPanel
    private var mouseTimer: Timer?
    private var wasInside = false
    private var scrollMonitor: Any?
    private var scrollTotal: CGFloat = 0
    private var scrollConsumed = false

    init(model: IslandModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))
        let host = FirstMouseHostingView(rootView: IslandView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
    }

    var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first ?? NSScreen.main!
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.trackMouse() }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }

    func reposition() {
        let s = screen
        model.updateGeometry(for: s)
        let frame = NSRect(x: s.frame.midX - Self.canvas.width / 2,
                           y: s.frame.maxY - Self.canvas.height,
                           width: Self.canvas.width, height: Self.canvas.height)
        panel.setFrame(frame, display: true)
    }

    /// Two-finger horizontal swipe on the trackpad hides the current activity.
    private func handleScroll(_ event: NSEvent) {
        guard event.window === panel, event.momentumPhase.isEmpty else { return }
        if event.phase == .began || event.phase.isEmpty && !event.hasPreciseScrollingDeltas {
            scrollTotal = 0
            scrollConsumed = false
        }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        scrollTotal += event.scrollingDeltaX
        if !scrollConsumed && abs(scrollTotal) > 45 {
            scrollConsumed = true
            model.swipeAway(direction: scrollTotal)
        }
    }

    private func trackMouse() {
        let s = screen
        let m = model.metrics
        var width = m.size.width
        if model.secondary != nil { width += 2 * (model.bubbleDiameter + IslandModel.bubbleGap) }
        let top = s.frame.maxY - model.topOffset
        // A little slack so the idle island (which hides in the notch) is easy to hit.
        let slack: CGFloat = model.isExpanded ? 6 : 3
        let rect = NSRect(x: s.frame.midX - width / 2 - slack, y: top - m.size.height - slack,
                          width: width + slack * 2, height: m.size.height + slack + 1)
        // Keep the island open while a drag that started on it (e.g. scrubbing) wanders off.
        let inside = rect.contains(NSEvent.mouseLocation) || (wasInside && NSEvent.pressedMouseButtons != 0)
        wasInside = inside
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.setHovering(inside)
    }
}
