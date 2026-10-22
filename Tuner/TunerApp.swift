import SwiftUI

@main
struct TunerApp: App {
    @State private var radio: Radio

    init() {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
            Snapshot.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        if CommandLine.arguments.contains("--selftest") {
            // Its own defaults, so muting the test doesn't mute the real app.
            let radio = Radio(defaults: UserDefaults(suiteName: "selftest")!)
            SelfTest.run(radio)
            _radio = State(initialValue: radio)
            return
        }
        #endif
        let radio = Radio()
        radio.startRefreshing()
        _radio = State(initialValue: radio)
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(radio: radio)
        } label: {
            Image(nsImage: MenuBarIcon.image(position: radio.dialPosition, of: radio.mixtapes.count, channel: radio.station.channel, playing: radio.isOn))
                .accessibilityLabel(radio.isOn ? "Tuner, playing \(radio.station.name)" : "Tuner")
        }
        .menuBarExtraStyle(.window)
    }
}
