import AppKit
import Combine
import SwiftUI

enum IslandStyle: String, CaseIterable {
    case notch, pill
    var title: String { self == .notch ? "Notch (attached)" : "iPhone Pill (floating)" }
}

enum Activity: Hashable {
    case none, music, timer, charging, timerDone, lowBattery, bluetooth, volume
}

/// Row heights of the expanded island, shared by the views and the size math
/// so the black shape always matches what's drawn inside it.
enum ExpandedLayout {
    static let music: CGFloat = 112
    static let idle: CGFloat = 96
    static let timer: CGFloat = 28
    static let spacing: CGFloat = 10
    static let bottomPadding: CGFloat = 14
}

struct IslandMetrics: Equatable {
    var size: CGSize
    var topInverted: CGFloat   // concave "ears" that blend into the menu bar
    var topConvex: CGFloat     // rounded top corners (pill style)
    var bottom: CGFloat
}

final class IslandModel: ObservableObject {
    static let bubbleGap: CGFloat = 6
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.74)

    @Published var isExpanded = false
    @Published private(set) var transient: Activity?
    @Published var style: IslandStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") }
    }
    @Published var expandOnHover: Bool {
        didSet { UserDefaults.standard.set(expandOnHover, forKey: "expandOnHover") }
    }
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var hasNotch = false
    /// Live activities the user swiped away; they come back on their next update.
    @Published private(set) var hidden: Set<Activity> = []
    @Published private(set) var swipeOffset: CGFloat = 0

    let nowPlaying = NowPlayingService()
    let battery = BatteryService()
    let timer = TimerService()
    let bluetooth = BluetoothService()
    let volume = VolumeService()

    private var hovering = false
    private var hoverWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?
    private var bag = Set<AnyCancellable>()

    init() {
        style = IslandStyle(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .notch
        expandOnHover = UserDefaults.standard.object(forKey: "expandOnHover") as? Bool ?? true

        for publisher in [nowPlaying.objectWillChange, battery.objectWillChange, timer.objectWillChange,
                          bluetooth.objectWillChange, volume.objectWillChange] {
            publisher.receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &bag)
        }
        battery.onPlugIn = { [weak self] in self?.showTransient(.charging) }
        battery.onLowBattery = { [weak self] in self?.showTransient(.lowBattery, duration: 4) }
        bluetooth.onConnect = { [weak self] in self?.showTransient(.bluetooth, duration: 4) }
        volume.onChange = { [weak self] in self?.showTransient(.volume, duration: 1.6) }

        // A hidden activity returns when something new happens to it, as on iPhone.
        nowPlaying.$track.map { $0?.title }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.hidden.remove(.music) }
            .store(in: &bag)
        nowPlaying.$isPlaying.removeDuplicates().filter { $0 }
            .sink { [weak self] _ in self?.hidden.remove(.music) }
            .store(in: &bag)
        timer.$endDate.compactMap { $0 }
            .sink { [weak self] _ in self?.hidden.remove(.timer) }
            .store(in: &bag)
        timer.onFinish = { [weak self] in
            NSSound(named: "Glass")?.play()
            self?.showTransient(.timerDone, duration: 4)
        }
    }

    func start() {
        nowPlaying.start()
        battery.start()
        bluetooth.start()
        volume.start()
    }

    func updateGeometry(for screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                               height: screen.safeAreaInsets.top)
        } else {
            hasNotch = false
            let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            notchSize = CGSize(width: 185, height: menuBar)
        }
    }

    // MARK: Activities

    var primary: Activity {
        if let transient { return transient }
        if showsMusic { return .music }
        if showsTimer { return .timer }
        return .none
    }

    private var showsMusic: Bool { nowPlaying.isPlaying && !hidden.contains(.music) }
    private var showsTimer: Bool { timer.isActive && !hidden.contains(.timer) }

    /// iPhone splits into a second floating bubble when two live activities run at once.
    var secondary: Activity? {
        transient == nil && showsMusic && showsTimer && !isExpanded ? .timer : nil
    }

    /// Swipe sideways to tuck the current activity away: the content slides off
    /// in the swipe direction, then the island shrinks back into the notch.
    func swipeAway(direction: CGFloat) {
        let target = primary
        guard target != .none, swipeOffset == 0 else { return }
        withAnimation(.easeIn(duration: 0.14)) { swipeOffset = direction < 0 ? -50 : 50 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [self] in
            withAnimation(Self.spring) {
                if transient != nil {
                    transientWork?.cancel()
                    transient = nil
                } else {
                    hidden.insert(target)
                }
                isExpanded = false
                swipeOffset = 0
            }
        }
    }

    func showTransient(_ activity: Activity, duration: TimeInterval = 3) {
        transientWork?.cancel()
        withAnimation(Self.spring) { transient = activity }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.spring) { self?.transient = nil }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: Expansion

    func setHovering(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if inside && self.expandOnHover { self.setExpanded(true) }
            if !inside { self.setExpanded(false) }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.12 : 0.25), execute: work)
    }

    func setExpanded(_ value: Bool) {
        guard value != isExpanded else { return }
        if value { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        withAnimation(Self.spring) { isExpanded = value }
    }

    // MARK: Geometry

    var isPill: Bool { style == .pill }
    var topOffset: CGFloat { isPill ? 5 : 0 }
    var islandHeight: CGFloat { isPill ? max(30, notchSize.height - 4) : notchSize.height }
    var bubbleDiameter: CGFloat { islandHeight }
    var idleWidth: CGFloat { isPill ? 170 : notchSize.width }

    func compactSideWidth(for activity: Activity) -> CGFloat {
        switch activity {
        case .none: return 0
        case .charging, .timerDone, .lowBattery, .volume: return 92
        case .bluetooth: return 66
        case .music, .timer: return islandHeight + 14
        }
    }

    var metrics: IslandMetrics {
        let h = islandHeight
        if isExpanded {
            let header: CGFloat = isPill ? 30 : notchSize.height
            let main = nowPlaying.track != nil ? ExpandedLayout.music : ExpandedLayout.idle
            let height = header + main + ExpandedLayout.timer + ExpandedLayout.spacing * 2 + ExpandedLayout.bottomPadding
            let size = CGSize(width: max(520, idleWidth + 260), height: height)
            return IslandMetrics(size: size, topInverted: isPill ? 0 : 14,
                                 topConvex: isPill ? 42 : 0, bottom: isPill ? 42 : 34)
        }
        let side = compactSideWidth(for: primary)
        let width = idleWidth + side * 2 + (isPill ? 0 : (primary == .none ? 0 : 12))
        if primary == .none {
            return IslandMetrics(size: CGSize(width: width, height: h), topInverted: 0,
                                 topConvex: isPill ? h / 2 : 0, bottom: isPill ? h / 2 : 10)
        }
        return IslandMetrics(size: CGSize(width: width, height: h), topInverted: isPill ? 0 : 6,
                             topConvex: isPill ? h / 2 : 0, bottom: isPill ? h / 2 : 12)
    }
}
