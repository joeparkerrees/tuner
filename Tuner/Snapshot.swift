#if DEBUG
import AppKit
import SwiftUI

/// `Tuner --snapshot <dir>` renders the panel offscreen with today's real
/// schedule and exits, so the UI can be checked without opening anything.
@MainActor
enum Snapshot {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schedules = (try? Data(contentsOf: NTS.liveURL)).flatMap { try? NTS.decode($0) } ?? [:]
        let poolside = Station.all.firstIndex { $0.id == "poolside" } ?? 2

        let states: [(name: String, tuned: Int, playing: Bool, icons: Bool)] = [
            ("nts1-playing", 0, true, false),
            ("nts2-stopped", 1, false, false),
            ("poolside-playing", poolside, true, false),
            ("poolside-icons", poolside, true, true),
        ]
        for state in states {
            let radio = Radio(defaults: UserDefaults(suiteName: "snapshot")!)
            radio.seedForSnapshot(tuned: state.tuned, playing: state.playing, schedules: schedules)
            let renderer = ImageRenderer(content: Panel(radio: radio, showsIcons: state.icons, playsIntro: false).fixedSize())
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: directory.appendingPathComponent("\(state.name).png"))
        }

        for (name, playing) in [("menubar-stopped", false), ("menubar-playing", true)] {
            let icon = MenuBarIcon.image(position: 0, of: 16, channel: nil, playing: playing)
            icon.size = NSSize(width: 72, height: 72)
            if let tiff = icon.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("\(name).png"))
            }
        }
    }
}
#endif

#if DEBUG
/// `Tuner --selftest` plays NTS 1 muted, retunes through a few stations the
/// way a drag would, prints each state and quits. It runs the Now Playing
/// artwork and KVO callbacks that only fire with real streams.
@MainActor
enum SelfTest {
    static func run(_ radio: Radio) {
        radio.volume = 0
        Task {
            @MainActor func report(_ label: String) {
                print(label, radio.station.name, radio.state)
                fflush(stdout)
            }
            await radio.refresh()
            radio.play(0)
            try? await Task.sleep(for: .seconds(6))
            report("after play")
            for index in [1, 2, 3, 4, 1] {
                radio.tune(to: index)
                try? await Task.sleep(for: .milliseconds(120))
            }
            try? await Task.sleep(for: .seconds(6))
            report("after drag")
            radio.step(-1)
            try? await Task.sleep(for: .seconds(6))
            report("after step")
            radio.stop()
            report("after stop")
            exit(0)
        }
    }
}
#endif
