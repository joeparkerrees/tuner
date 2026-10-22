import AppKit
import AVFoundation
import MediaPlayer
import Observation

@MainActor
@Observable
final class Radio {
    enum State: Equatable {
        case stopped, loading, playing, failed
    }

    let stations = Station.all
    /// The Infinite Mixtapes in dial order, as indices into `stations`. The
    /// live channels have their own keys and aren't on the dial.
    let mixtapes = Station.all.indices.filter { Station.all[$0].channel == nil }
    private(set) var tuned: Int
    /// Where the dial is set: the last mixtape tuned, kept while a live channel plays.
    private(set) var dialed: Int
    private(set) var state: State = .stopped
    private(set) var schedules: [String: Schedule] = [:]

    var volume: Double {
        didSet {
            player.volume = Float(volume)
            defaults.set(volume, forKey: Keys.volume)
        }
    }

    var station: Station { stations[tuned] }
    var dialPosition: Int { mixtapes.firstIndex(of: dialed) ?? 0 }
    var isOn: Bool { state == .loading || state == .playing }

    func schedule(for station: Station) -> Schedule? {
        station.channel.flatMap { schedules[$0] }
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var endObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var retuneTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var artwork: (url: URL, image: MPMediaItemArtwork)?
    @ObservationIgnored private var reconnects = 0

    private enum Keys {
        static let station = "station"
        static let dialed = "dialed"
        static let volume = "volume"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: Keys.station)
        tuned = Station.all.firstIndex { $0.id == saved } ?? 0
        let savedDial = defaults.string(forKey: Keys.dialed)
        dialed = Station.all.firstIndex { $0.id == savedDial && $0.channel == nil }
            ?? Station.all.firstIndex { $0.channel == nil } ?? 0
        // Opening a radio that's silent looks broken, so a saved zero starts at the default.
        let savedVolume = defaults.object(forKey: Keys.volume) as? Double ?? 0
        volume = savedVolume > 0.02 ? savedVolume : 0.8
        player.volume = Float(volume)
        player.automaticallyWaitsToMinimizeStalling = true
        configureRemoteCommands()
    }

    // MARK: Tuning

    func tune(to index: Int) {
        let index = ((index % stations.count) + stations.count) % stations.count
        guard index != tuned else { return }
        tuned = index
        defaults.set(station.id, forKey: Keys.station)
        if station.channel == nil {
            dialed = index
            defaults.set(station.id, forKey: Keys.dialed)
        }

        if isOn || state == .failed && retuneTask != nil {
            // Let the dial settle before opening a stream, so a fast spin
            // through six stations doesn't open six connections.
            retuneTask?.cancel()
            teardown()
            state = .loading
            retuneTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                self?.start()
            }
        }
        publishNowPlaying()
    }

    /// Turns the dial, which only ever lands on mixtapes.
    func step(_ delta: Int) {
        dial(to: dialPosition + delta)
    }

    func dial(to position: Int) {
        let count = mixtapes.count
        tune(to: mixtapes[((position % count) + count) % count])
    }

    // MARK: Transport

    func toggle() {
        isOn ? stop() : play()
    }

    func play() {
        retuneTask?.cancel()
        reconnects = 0
        start()
    }

    func play(_ index: Int) {
        tune(to: index)
        play()
    }

    func stop() {
        retuneTask?.cancel()
        teardown()
        state = .stopped
        publishNowPlaying()
    }

    private func start() {
        teardown()
        let item = AVPlayerItem(url: station.stream)
        // A radio should make sound when you turn it. Starting on a one second
        // buffer gets NTS going in ~0.7s instead of ~3.4s; see timeControlChanged.
        item.preferredForwardBufferDuration = 1
        player.replaceCurrentItem(with: item)
        state = .loading
        observe(item)
        player.play()
        armTimeout()
        publishNowPlaying()
    }

    private func teardown() {
        timeoutTask?.cancel()
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        endObservers.forEach(NotificationCenter.default.removeObserver)
        endObservers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func observe(_ item: AVPlayerItem) {
        observations = Self.watch(player, item, for: self)

        // Icecast streams occasionally drop. Reconnect quietly a few times
        // before admitting defeat.
        for name in [AVPlayerItem.failedToPlayToEndTimeNotification, AVPlayerItem.didPlayToEndTimeNotification] {
            endObservers.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reconnect() }
            })
        }
    }

    private func timeControlChanged(_ status: AVPlayer.TimeControlStatus) {
        guard isOn else { return }
        switch status {
        case .playing:
            timeoutTask?.cancel()
            reconnects = 0
            // Once it's playing, let AVPlayer build its usual cushion against dropouts.
            player.currentItem?.preferredForwardBufferDuration = 0
            state = .playing
            publishNowPlaying()
        case .waitingToPlayAtSpecifiedRate:
            if state == .playing {
                state = .loading
                armTimeout()
            }
        default:
            break
        }
    }

    private func armTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, self?.state == .loading else { return }
            self?.fail()
        }
    }

    private func reconnect() {
        guard isOn else { return }
        guard reconnects < 3 else { return fail() }
        reconnects += 1
        start()
    }

    private func fail() {
        teardown()
        state = .failed
        publishNowPlaying()
    }

    // MARK: Schedule

    func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(self.secondsUntilNextRefresh()))
            }
        }
    }

    func refresh() async {
        guard let schedules = try? await NTS.live() else { return }
        guard schedules != self.schedules else { return }
        self.schedules = schedules
        publishNowPlaying()
    }

    /// Every minute, or just after the next show change if that comes sooner.
    private func secondsUntilNextRefresh() -> Double {
        let nextChange = schedules.values.map(\.now.end).min()
        guard let nextChange else { return 60 }
        return min(60, max(5, nextChange.timeIntervalSinceNow + 4))
    }

    // MARK: Now Playing

    private func publishNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard state != .stopped else {
            center.playbackState = .stopped
            return
        }

        let show = schedule(for: station)?.now
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: show?.title ?? station.name,
            MPMediaItemPropertyArtist: station.channel == nil ? "NTS Infinite Mixtapes" : station.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let url = show?.artwork {
            if artwork?.url == url {
                info[MPMediaItemPropertyArtwork] = artwork?.image
            } else {
                loadArtwork(url)
            }
        }
        center.nowPlayingInfo = info
        center.playbackState = state == .playing ? .playing : .paused
    }

    private func loadArtwork(_ url: URL) {
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            let artwork = Self.artwork(image)
            self?.artwork = (url, artwork)
            self?.publishNowPlaying()
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        let bindings: [(MPRemoteCommand, @MainActor @Sendable (Radio) -> Void)] = [
            (commands.togglePlayPauseCommand, { $0.toggle() }),
            (commands.playCommand, { $0.play() }),
            (commands.pauseCommand, { $0.stop() }),
            (commands.stopCommand, { $0.stop() }),
            (commands.nextTrackCommand, { $0.step(1) }),
            (commands.previousTrackCommand, { $0.step(-1) }),
        ]
        for (command, action) in bindings {
            Self.bind(command, to: self, action)
        }
    }

    // MARK: Callbacks from other queues
    //
    // MediaPlayer and KVO call these closures on their own queues. Written
    // inside a main actor method, Swift 6 would tie them to the main thread
    // and trap when they're called from anywhere else, so they're built here
    // and hop back to the main actor themselves.

    nonisolated private static func watch(_ player: AVPlayer, _ item: AVPlayerItem, for radio: Radio) -> [NSKeyValueObservation] {
        [
            player.observe(\.timeControlStatus, options: [.new]) { [weak radio] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor in radio?.timeControlChanged(status) }
            },
            item.observe(\.status, options: [.new]) { [weak radio] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in radio?.fail() }
            },
        ]
    }

    nonisolated private static func artwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    nonisolated private static func bind(_ command: MPRemoteCommand, to radio: Radio, _ action: @escaping @MainActor @Sendable (Radio) -> Void) {
        command.isEnabled = true
        command.addTarget { [weak radio] _ in
            Task { @MainActor in
                guard let radio else { return }
                action(radio)
            }
            return .success
        }
    }
}

#if DEBUG
extension Radio {
    /// Seeds a believable state for headless snapshots.
    func seedForSnapshot(tuned index: Int, playing: Bool, schedules: [String: Schedule]) {
        tuned = index
        if stations[index].channel == nil { dialed = index }
        self.schedules = schedules
        state = playing ? .playing : .stopped
    }
}
#endif
