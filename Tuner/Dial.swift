import AppKit
import SwiftUI

/// The mixtape dial. A white disc with each Infinite Mixtape as a dot in a
/// ring, like the dot index on a Braun clock, and a black bead that rides the ring to whichever one is dialled.
/// Point at the dial and the dots turn into NTS's mixtape icons, with the
/// bead carrying the dialled one. While a live channel is on, the bead goes
/// hollow: the dial is still set there, it just isn't what's playing. Drag
/// or click the ring to tune, click the middle to play or stop.
struct Dial: View {
    let radio: Radio
    var size: CGFloat
    /// Holds the icons open without a pointer, for snapshots.
    var showsIcons: Bool
    /// A station to show in the middle from outside the dial, like a hovered channel key.
    var previewing: Int?

    @State private var beadAngle: Double
    @State private var pointerInside = false
    /// A dial position under the pointer.
    @State private var hovered: Int?
    @State private var grab: Grab?
    @State private var pressingCenter = false

    private enum Grab { case ring, center }

    init(radio: Radio, size: CGFloat = Theme.panelWidth - Theme.gutter * 2, showsIcons: Bool = false, previewing: Int? = nil) {
        self.radio = radio
        self.size = size
        self.showsIcons = showsIcons
        self.previewing = previewing
        _beadAngle = State(initialValue: Double(radio.dialPosition) * 360 / Double(radio.mixtapes.count))
    }

    private var radius: CGFloat { size / 2 }
    /// Where the dots sit. There's no drawn ring, the dots make the circle.
    private var ringRadius: CGFloat { radius - 17.5 }
    /// Anything closer to the middle than this is the play/stop button.
    private var centerRadius: CGFloat { ringRadius - 26 }
    private var count: Int { radio.mixtapes.count }
    private var step: Double { 360 / Double(count) }
    private var revealed: Bool { showsIcons || pointerInside || grab == .ring }
    /// True while NTS 1 or 2 is tuned, so the dial is set but not playing.
    private var dialIsIdle: Bool { radio.station.channel != nil }
    /// The station shown in the middle: a hovered mixtape, a hovered key, or nothing.
    private var highlighted: Int? { hovered.map { radio.mixtapes[$0] } ?? previewing }

    private let reveal = Animation.spring(duration: 0.4, bounce: 0.25)

    var body: some View {
        ZStack {
            Circle().fill(Theme.paper)

            ForEach(0..<count, id: \.self) { position in
                mark(position)
            }

            bead

            Readout(radio: radio, previewing: highlighted.map { radio.stations[$0] })
                .frame(width: centerRadius * 2 - 20)
        }
        .frame(width: size, height: size)
        .scaleEffect(pressingCenter ? 0.985 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressingCenter)
        .contentShape(Circle())
        .gesture(drag)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                pointerInside = true
                let distance = distanceFromCenter(point)
                hovered = distance > centerRadius && distance <= radius ? position(at: point) : nil
            case .ended:
                pointerInside = false
                hovered = nil
            }
        }
        .onChange(of: radio.dialPosition) { old, new in
            withAnimation(Theme.detent) {
                beadAngle += shortestTurn(from: old, to: new) * step
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mixtape dial")
        .accessibilityValue(radio.stations[radio.dialed].name)
        .accessibilityAdjustableAction { direction in
            radio.step(direction == .increment ? 1 : -1)
        }
        .accessibilityAction(named: radio.isOn ? "Stop" : "Play") { radio.toggle() }
    }

    /// A dot at rest, the mixtape's icon while you're pointing at the dial.
    /// Icons stay upright as they go round, like the numbers on a clock.
    private func mark(_ position: Int) -> some View {
        let station = radio.stations[radio.mixtapes[position]]
        let isDialed = position == radio.dialPosition
        let isHovered = highlighted == radio.mixtapes[position] && !isDialed
        let angle = Double(position) * step * .pi / 180
        // The icons ripple out from the bead as they appear.
        let delay = revealed ? abs(shortestTurn(from: radio.dialPosition, to: position)) * 0.014 : 0

        return ZStack {
            Circle()
                .fill(Theme.faint)
                .frame(width: 3, height: 3)
                .opacity(revealed ? 0 : 1)
            StationIcon(station: station)
                .frame(width: 18, height: 18)
                .foregroundStyle(isHovered ? Theme.ink : Theme.muted)
                .scaleEffect(revealed ? (isHovered ? 1.12 : 1) : 0.2)
                .opacity(revealed ? 1 : 0)
        }
        // The bead covers whichever mixtape is dialled.
        .opacity(isDialed ? 0 : 1)
        .position(x: radius + ringRadius * sin(angle), y: radius - ringRadius * cos(angle))
        .animation(reveal.delay(delay), value: revealed)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: radio.dialPosition)
    }

    /// The solid bead grows from a dot into a disc carrying the dialled
    /// mixtape's icon. While a live channel is on the bead is hollow, and a
    /// thin ring stretching to four times its size reads as a ripple running
    /// outwards, so the small ring and the ringed icon swap in place instead.
    /// The icon is counter-rotated so it stays upright while the bead travels.
    private var bead: some View {
        let icon = StationIcon(station: radio.stations[radio.dialed])
            .frame(width: 15, height: 15)
            .id(radio.dialed)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .rotationEffect(.degrees(-beadAngle))

        return ZStack {
            if dialIsIdle {
                Circle()
                    .fill(Theme.paper)
                    .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(revealed ? 0.4 : 1)
                    .opacity(revealed ? 0 : 1)
                ZStack {
                    Circle().fill(Theme.paper)
                    Circle().strokeBorder(Theme.ink, lineWidth: 1.5)
                    icon.foregroundStyle(Theme.ink)
                }
                .frame(width: 30, height: 30)
                .scaleEffect(revealed ? 1 : 0.7)
                .opacity(revealed ? 1 : 0)
            } else {
                ZStack {
                    Circle().fill(Theme.ink)
                    icon
                        .foregroundStyle(Theme.paper)
                        .scaleEffect(revealed ? 1 : 0.3)
                        .opacity(revealed ? 1 : 0)
                }
                .frame(width: revealed ? 30 : 7, height: revealed ? 30 : 7)
            }
        }
        .animation(dialIsIdle ? .spring(duration: 0.3, bounce: 0.1) : reveal, value: revealed)
        .animation(.easeOut(duration: 0.2), value: dialIsIdle)
        .offset(y: -ringRadius)
        .rotationEffect(.degrees(beadAngle))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grab == nil {
                    grab = distanceFromCenter(value.startLocation) < centerRadius ? .center : .ring
                }
                switch grab {
                case .ring:
                    // Ignore the dead zone at the very middle where angle is noise.
                    guard distanceFromCenter(value.location) > 12 else { return }
                    let target = radio.mixtapes[position(at: value.location)]
                    guard target != radio.tuned else { return }
                    radio.tune(to: target)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                case .center:
                    pressingCenter = distanceFromCenter(value.location) < centerRadius
                case nil:
                    break
                }
            }
            .onEnded { value in
                if grab == .center, distanceFromCenter(value.location) < centerRadius {
                    radio.toggle()
                }
                grab = nil
                pressingCenter = false
            }
    }

    private func distanceFromCenter(_ point: CGPoint) -> CGFloat {
        hypot(point.x - radius, point.y - radius)
    }

    /// Nearest dial position to a point, clockwise from twelve o'clock.
    private func position(at point: CGPoint) -> Int {
        var degrees = atan2(point.x - radius, radius - point.y) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return Int((degrees / step).rounded()) % count
    }

    private func shortestTurn(from old: Int, to new: Int) -> Double {
        var delta = (new - old) % count
        if delta > count / 2 { delta -= count }
        if delta < -count / 2 { delta += count }
        return Double(delta)
    }
}

/// NTS's own mixtape icons, and for the live channels the numbered square
/// nts.live uses, drawn here so it stays sharp at any size.
struct StationIcon: View {
    let station: Station

    var body: some View {
        if let channel = station.channel {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: geometry.size.width * 0.14)
                    .overlay {
                        Text(channel)
                            .font(.system(size: geometry.size.width * 0.72, weight: .semibold))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
        } else {
            Image(station.id)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .scaledToFit()
        }
    }
}

/// What's in the middle of the dial: the tuned station, or the one under the
/// pointer while you hover the ring.
private struct Readout: View {
    let radio: Radio
    let previewing: Station?

    private var station: Station { previewing ?? radio.station }
    private var isTunedStation: Bool { station == radio.station }

    var body: some View {
        let schedule = radio.schedule(for: station)
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                if isTunedStation, radio.state == .playing {
                    Circle().fill(Theme.red).frame(width: 5, height: 5)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(station.channel == nil ? "Mixtape" : station.name)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.muted)

            Text(schedule?.now.title ?? station.name)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .lineLimit(3)

            Text(detail(schedule))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(station.channel == nil ? 4 : 2)
                .monospacedDigit()
        }
        .multilineTextAlignment(.center)
        .id(station.id)
        .transition(.opacity.combined(with: .offset(y: 3)))
        .animation(Theme.settle, value: station.id)
        .animation(Theme.settle, value: radio.state)
    }

    private func detail(_ schedule: Schedule?) -> String {
        if isTunedStation, radio.state == .failed {
            return "Couldn’t connect. Click to try again."
        }
        guard station.channel != nil else { return station.blurb }
        guard let now = schedule?.now else { return "Live" }
        let until = "Until \(now.end.formatted(date: .omitted, time: .shortened))"
        return [now.location, until].compactMap { $0 }.joined(separator: " · ")
    }
}
