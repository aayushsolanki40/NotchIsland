import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        let m = model.metrics
        let shape = IslandShape(topInverted: m.topInverted, topConvex: m.topConvex, bottom: m.bottom)
        ZStack(alignment: .top) {
            content
                .offset(x: model.swipeOffset)
                .opacity(1 - Double(abs(model.swipeOffset)) / 80)
                .padding(.horizontal, m.topInverted)
                .frame(width: m.size.width + m.topInverted * 2, height: m.size.height, alignment: .top)
                .background(shape.fill(Color.black))
                .clipShape(shape)
                .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 18, y: 8)
                .contentShape(shape)
                // Only the collapsed island is tappable as a whole; once expanded the
                // gesture steps aside so it can't swallow clicks meant for the controls.
                .gesture(TapGesture().onEnded { model.setExpanded(true) },
                         including: model.isExpanded ? .subviews : .all)
                // Click-and-drag sideways also hides the activity (for mice / hover off).
                .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                    let dx = value.translation.width
                    if abs(dx) > 40 && abs(dx) > abs(value.translation.height) { model.swipeAway(direction: dx) }
                }, including: model.isExpanded ? .subviews : .all)
                .overlay(alignment: .trailing) {
                    if let secondary = model.secondary {
                        bubble(secondary)
                            .offset(x: model.bubbleDiameter + IslandModel.bubbleGap)
                            .transition(.blurFade)
                    }
                }
        }
        .padding(.top, model.topOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(IslandModel.spring, value: m)
        .animation(IslandModel.spring, value: model.primary)
    }

    @ViewBuilder private var content: some View {
        if model.isExpanded {
            ExpandedView(model: model)
                .transition(.blurFade)
        } else if model.primary != .none {
            CompactView(model: model, activity: model.primary)
                .id(model.primary)
                .transition(.blurFade)
        }
    }

    private func bubble(_ activity: Activity) -> some View {
        Circle().fill(Color.black)
            .frame(width: model.bubbleDiameter, height: model.bubbleDiameter)
            .overlay { TimerRing(timer: model.timer, size: model.bubbleDiameter - 12) }
    }
}

// MARK: - Compact

struct CompactView: View {
    @ObservedObject var model: IslandModel
    let activity: Activity

    var body: some View {
        let side = model.compactSideWidth(for: activity)
        let h = model.islandHeight
        HStack(spacing: 0) {
            leading.frame(width: side, alignment: .leading).padding(.leading, 8)
            Spacer(minLength: model.idleWidth - 16)
            trailing.frame(width: side, alignment: .trailing).padding(.trailing, 8)
        }
        .frame(height: h)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case .music:
            Artwork(image: model.nowPlaying.artwork, size: model.islandHeight - 10, radius: 6)
        case .timer:
            Image(systemName: "timer").font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
        case .charging:
            Text(model.battery.isCharging || !model.battery.hasBattery ? "Charging" : "Connected")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
        case .timerDone:
            Label("Timer", systemImage: "timer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
        case .lowBattery:
            Text("Low Battery").font(.system(size: 13, weight: .medium)).foregroundStyle(.red)
        case .bluetooth:
            Image(systemName: model.bluetooth.lastConnected?.symbol ?? "headphones")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                .help(model.bluetooth.lastConnected?.name ?? "")
        case .volume:
            Image(systemName: model.volume.symbol)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, alignment: .leading)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .music:
            Waveform(color: model.nowPlaying.accent, playing: model.nowPlaying.isPlaying)
                .frame(width: 20, height: 14)
        case .timer:
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                Text(formatDuration(model.timer.remaining(at: ctx.date)))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText(countsDown: true))
            }
        case .charging:
            BatteryGlyph(level: model.battery.hasBattery ? model.battery.level : 100, charging: true, showPercent: true)
        case .timerDone:
            Text("Done").font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
        case .lowBattery:
            BatteryGlyph(level: model.battery.alertLevel, charging: false, showPercent: true)
        case .bluetooth:
            if let battery = model.bluetooth.lastConnected?.battery {
                BatteryRing(level: battery)
            } else {
                Text("Connected").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize()
            }
        case .volume:
            LevelBar(level: model.volume.muted ? 0 : CGFloat(model.volume.level))
                .frame(width: 64, height: 6)
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: ExpandedLayout.spacing) {
            header
            if model.nowPlaying.track != nil {
                MusicPlayer(nowPlaying: model.nowPlaying)
            } else {
                IdlePanel()
            }
            TimerBar(timer: model.timer)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, ExpandedLayout.bottomPadding)
    }

    /// Lives in the notch row, split around the camera housing.
    private var header: some View {
        HStack {
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: model.isPill ? 0 : model.notchSize.width)
            if model.battery.hasBattery {
                BatteryGlyph(level: model.battery.level, charging: model.battery.isPluggedIn, showPercent: true)
            }
        }
        .frame(height: model.isPill ? 30 : model.notchSize.height)
        .padding(.horizontal, model.isPill ? 12 : 0)
    }
}

struct IdlePanel: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 46, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "music.note").font(.system(size: 18)).foregroundStyle(.white.opacity(0.35))
                Text("Play something in Music or Spotify")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(height: ExpandedLayout.idle)
    }
}

struct MusicPlayer: View {
    @ObservedObject var nowPlaying: NowPlayingService
    /// Position under the finger while dragging the progress bar.
    @State private var scrub: Double?

    var body: some View {
        let track = nowPlaying.track!
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Artwork(image: nowPlaying.artwork, size: 52, radius: 12)
                    .onTapGesture(perform: nowPlaying.openSource)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                Spacer()
                Waveform(color: nowPlaying.accent, playing: nowPlaying.isPlaying).frame(width: 22, height: 16)
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let pos = scrub ?? nowPlaying.currentPosition(at: ctx.date)
                HStack(spacing: 8) {
                    Text(formatDuration(pos)).frame(width: 36, alignment: .leading)
                    GeometryReader { geo in
                        LevelBar(level: track.duration > 0 ? pos / track.duration : 0)
                            .frame(height: scrub == nil ? 5 : 9)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    let fraction = min(max(0, v.location.x / geo.size.width), 1)
                                    withAnimation(.easeOut(duration: 0.12)) { scrub = fraction * track.duration }
                                }
                                .onEnded { _ in
                                    if let scrub { nowPlaying.seek(to: scrub) }
                                    withAnimation(.easeOut(duration: 0.2)) { scrub = nil }
                                })
                    }
                    .frame(height: 14)
                    Text("-" + formatDuration(max(0, track.duration - pos))).frame(width: 40, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 34) {
                ControlButton(symbol: "backward.fill", size: 16, action: nowPlaying.previous)
                ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 22, action: nowPlaying.playPause)
                ControlButton(symbol: "forward.fill", size: 16, action: nowPlaying.next)
            }
        }
        .frame(height: ExpandedLayout.music)
    }
}

struct TimerBar: View {
    @ObservedObject var timer: TimerService
    private let presets: [(String, TimeInterval)] = [("1m", 60), ("5m", 300), ("10m", 600), ("25m", 1500)]

    var body: some View {
        HStack(spacing: 8) {
            if timer.isActive {
                TimerRing(timer: timer, size: 20)
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    Text(formatDuration(timer.remaining(at: ctx.date)))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                Spacer()
                CircleButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", tint: .orange, action: timer.togglePause)
                CircleButton(symbol: "xmark", tint: .gray, action: timer.cancel)
            } else {
                Image(systemName: "timer").foregroundStyle(.orange).font(.system(size: 13, weight: .semibold))
                Spacer()
                ForEach(presets, id: \.1) { label, secs in
                    Button { timer.start(seconds: secs) } label: {
                        Text(label).font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: ExpandedLayout.timer)
    }
}

// MARK: - Pieces

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct Waveform: View {
    let color: Color
    let playing: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        let phase = sin(t * (5 + Double(i) * 1.7) + Double(i) * 1.3) * 0.5 + 0.5
                        Capsule().fill(color)
                            .frame(height: geo.size.height * (playing ? 0.25 + 0.75 * phase : 0.2))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct BatteryGlyph: View {
    let level: Int
    let charging: Bool
    let showPercent: Bool

    private var color: Color { charging ? .green : (level <= 20 ? .red : .white) }

    var body: some View {
        HStack(spacing: 5) {
            if showPercent {
                Text("\(level)%").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(color)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1)
                    .frame(width: 24, height: 12)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color)
                    .frame(width: max(2, 20 * CGFloat(level) / 100), height: 8)
                    .padding(.leading, 2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black).frame(width: 24)
                }
            }
            .overlay(alignment: .trailing) {
                Capsule().fill(.white.opacity(0.4)).frame(width: 1.5, height: 4).offset(x: 2.5)
            }
        }
    }
}

struct LevelBar: View {
    let level: CGFloat

    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: geo.size.width * min(max(level, 0), 1))
                }
        }
    }
}

/// The green ring iOS shows when AirPods connect.
struct BatteryRing: View {
    let level: Int

    private var color: Color { level <= 20 ? .red : .green }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(level)%").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(color)
            ZStack {
                Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
                Circle().trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
    }
}

struct TimerRing: View {
    @ObservedObject var timer: TimerService
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            ZStack {
                Circle().stroke(Color.orange.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: timer.progress(at: ctx.date))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
        }
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 30)
                .background(Circle().fill(.white.opacity(hovering ? 0.12 : 0)).frame(width: 34, height: 34))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CircleButton: View {
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.22)))
        }
        .buttonStyle(.plain)
    }
}
