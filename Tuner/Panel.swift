import AppKit
import SwiftUI

/// Everything that drops out of the menu bar.
struct Panel: View {
    @Bindable var radio: Radio
    /// Snapshots only: shows the dial's icons without a pointer over it.
    var showsIcons = false
    @FocusState private var focused: Bool
    @State private var scroll = ScrollTuner()
    /// A live channel row under the pointer, previewed in the middle of the dial.
    @State private var previewing: Int?

    var body: some View {
        VStack(spacing: Theme.gutter) {
            Dial(radio: radio, showsIcons: showsIcons, previewing: previewing)
            Transport(radio: radio)
            Channels(radio: radio, previewing: $previewing)
            Footer()
        }
        .padding(Theme.gutter)
        .frame(width: Theme.panelWidth)
        .background(Theme.ground)
        .environment(\.colorScheme, .light)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .upArrow]) { _ in
            radio.step(-1)
            return .handled
        }
        .onKeyPress(keys: [.rightArrow, .downArrow]) { _ in
            radio.step(1)
            return .handled
        }
        .onKeyPress(.space) {
            radio.toggle()
            return .handled
        }
        .onKeyPress(characters: ["q"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            NSApp.terminate(nil)
            return .handled
        }
        .contextMenu {
            Button("Quit Tuner") { NSApp.terminate(nil) }
        }
        .onAppear {
            focused = true
            scroll.install(radio)
            Task { await radio.refresh() }
        }
        .onDisappear { scroll.remove() }
    }
}

/// Two-finger scroll or a mouse wheel turns the dial, one detent per notch.
@MainActor
private final class ScrollTuner {
    private var monitor: Any?
    private var travel: CGFloat = 0
    private let detent: CGFloat = 18

    func install(_ radio: Radio) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, radio) }
            return event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent, _ radio: Radio) {
        // Momentum would spin you past where your fingers stopped.
        guard event.momentumPhase.isEmpty else { return }
        if event.phase == .began { travel = 0 }

        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : -event.scrollingDeltaX
        guard delta != 0 else { return }

        guard event.hasPreciseScrollingDeltas else {
            radio.step(delta > 0 ? -1 : 1)
            return
        }
        travel += delta
        while abs(travel) >= detent {
            let direction: CGFloat = travel > 0 ? 1 : -1
            radio.step(direction > 0 ? -1 : 1)
            travel -= direction * detent
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

// MARK: Transport

private struct Transport: View {
    @Bindable var radio: Radio

    var body: some View {
        HStack(spacing: 14) {
            PlayButton(radio: radio)
            VolumeSlider(value: $radio.volume)
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
    }
}

private struct PlayButton: View {
    let radio: Radio
    @State private var hovering = false

    var body: some View {
        Button {
            radio.toggle()
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        } label: {
            ZStack {
                Circle().fill(Theme.ink)
                // Filled and stroked with round joins, so the corners come out soft.
                TransportGlyph(stop: radio.isOn ? 1 : 0)
                    .fill(Theme.paper)
                    .overlay {
                        TransportGlyph(stop: radio.isOn ? 1 : 0)
                            .stroke(Theme.paper, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    }
                    .animation(.snappy(duration: 0.32), value: radio.isOn)
            }
            .frame(width: 34, height: 34)
            .background {
                LoadingRing(active: radio.state == .loading)
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(PlayKey(hovering: hovering))
        .onHover { hovering = $0 }
        .accessibilityLabel(radio.isOn ? "Stop" : "Play")
    }
}

/// Dips fast when pressed and springs back past where it started, then
/// settles. Grows a touch under the pointer.
private struct PlayKey: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : (hovering ? 1.04 : 1))
            .animation(
                configuration.isPressed ? .easeOut(duration: 0.08) : .spring(response: 0.34, dampingFraction: 0.45),
                value: configuration.isPressed
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
    }
}

/// Play and stop as one shape. The triangle's tip is two points sitting on
/// top of each other, and they split into the square's right-hand corners,
/// so pressing play folds the triangle into stop.
private struct TransportGlyph: Shape {
    /// 0 is play, 1 is stop.
    var stop: Double

    var animatableData: Double {
        get { stop }
        set { stop = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Inset by the stroke so the rounded outline lands on these sizes.
        // The triangle sits right of centre because its visual weight is on the left.
        let play = CGRect(x: rect.midX - 3.4, y: rect.midY - 5, width: 8.6, height: 10)
        let square = CGRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8)
        let playPoints = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 1)]
        let stopPoints = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]

        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * stop }
        let box = CGRect(
            x: mix(play.minX, square.minX), y: mix(play.minY, square.minY),
            width: mix(play.width, square.width), height: mix(play.height, square.height)
        )
        let points = zip(playPoints, stopPoints).map { from, to in
            CGPoint(x: box.minX + mix(from.x, to.x) * box.width, y: box.minY + mix(from.y, to.y) * box.height)
        }

        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// A thin arc that goes round the button while a stream connects.
private struct LoadingRing: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360))
            }
        }
        .opacity(active ? 1 : 0)
        .scaleEffect(active ? 1 : 0.85)
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

/// Press: dip to 92% and spring back with a little overshoot.
struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

private struct VolumeSlider: View {
    @Binding var value: Double
    private let knob: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - knob
            let x = width * value
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 2)
                Capsule().fill(Theme.ink).frame(width: x + knob / 2, height: 2)
                Circle()
                    .fill(Theme.paper)
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(1, max(0, (drag.location.x - knob / 2) / width))
            })
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            value = min(1, max(0, value + (direction == .increment ? 0.1 : -0.1)))
        }
    }
}

// MARK: Live channels

/// Both live channels at a glance, so you can see what's on without tuning.
private struct Channels: View {
    let radio: Radio
    @Binding var previewing: Int?

    var body: some View {
        let live = radio.stations.indices.filter { radio.stations[$0].channel != nil }
        VStack(spacing: 0) {
            ForEach(Array(live.enumerated()), id: \.element) { position, index in
                if position > 0 {
                    Rectangle().fill(Theme.ground).frame(height: 1).padding(.leading, 50)
                }
                ChannelRow(radio: radio, index: index, previewing: $previewing)
            }
        }
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

private struct ChannelRow: View {
    let radio: Radio
    let index: Int
    @Binding var previewing: Int?
    @State private var hovering = false

    private var station: Station { radio.stations[index] }
    private var isRed: Bool { station.channel == "1" }
    private var isOn: Bool { radio.tuned == index && radio.isOn }

    var body: some View {
        let schedule = radio.schedule(for: station)
        Button {
            isOn ? radio.stop() : radio.play(index)
        } label: {
            HStack(spacing: 10) {
                // Red for 1 and white for 2, like the coloured keys on a Braun set.
                Text(station.channel ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isRed ? Theme.paper : Theme.ink)
                    .frame(width: 28, height: 28)
                    .background {
                        Circle().fill(isRed ? Theme.red : Theme.paper)
                        if !isRed { Circle().strokeBorder(Theme.line, lineWidth: 1) }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule?.now.title ?? station.name)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                    if let next = schedule?.next {
                        HStack(spacing: 6) {
                            Text(next.start.formatted(date: .omitted, time: .shortened))
                                .monospacedDigit()
                            Text(next.title)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 12)
            .padding(.trailing, 24)
            .padding(.vertical, 10)
            .overlay(alignment: .topTrailing) {
                // Lit while this channel is the one playing, blinking while it connects.
                Circle()
                    .fill(Theme.red)
                    .frame(width: 5, height: 5)
                    .opacity(isOn ? 1 : 0)
                    .phaseAnimator([1, 0.25], trigger: radio.state == .loading) { light, phase in
                        light.opacity(isOn && radio.state == .loading ? phase : 1)
                    } animation: { _ in .easeInOut(duration: 0.5) }
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .animation(.easeOut(duration: 0.15), value: isOn)
            }
            .background(hovering ? Theme.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { previewing = index } else if previewing == index { previewing = nil }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel("\(station.name), \(schedule?.now.title ?? "live")")
        .accessibilityValue(isOn ? "Playing" : "")
    }
}

// MARK: Footer

private struct Footer: View {
    @State private var hoveringDiscord = false

    var body: some View {
        HStack {
            Link("nts.live", destination: URL(string: "https://www.nts.live")!)
            Spacer()
            // The invite nts.live itself links to in its footer.
            Link(destination: URL(string: "https://discord.gg/nts-chat")!) {
                Image("discord")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(hoveringDiscord ? Theme.ink : Theme.muted)
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .onHover { hoveringDiscord = $0 }
            .animation(.easeOut(duration: 0.12), value: hoveringDiscord)
            .help("NTS on Discord")
            .accessibilityLabel("NTS on Discord")
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 4)
    }
}
