import Foundation

final class TimerService: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0

    var onFinish: (() -> Void)?
    private var ticker: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = Date()) -> Double {
        total > 0 ? remaining(at: date) / total : 0
    }

    func start(seconds: TimeInterval) {
        total = seconds
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(seconds)
        startTicker()
    }

    func togglePause() {
        if let pausedRemaining {
            endDate = Date().addingTimeInterval(pausedRemaining)
            self.pausedRemaining = nil
            startTicker()
        } else if endDate != nil {
            pausedRemaining = remaining()
            endDate = nil
            ticker?.invalidate()
        }
    }

    func cancel() {
        endDate = nil
        pausedRemaining = nil
        ticker?.invalidate()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let end = self.endDate, end <= Date() else { return }
            self.cancel()
            self.onFinish?()
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
}

func formatDuration(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.up))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}
