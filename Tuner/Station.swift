import Foundation

struct Station: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case live(channel: String)
        case mixtape
    }

    let id: String
    let name: String
    let kind: Kind
    let stream: URL
    /// NTS's own one-liner for a mixtape. Live channels get theirs from the schedule.
    let blurb: String

    var channel: String? {
        if case .live(let channel) = kind { channel } else { nil }
    }
}

extension Station {
    /// Dial order: the two live channels at the top of the scale, then the
    /// Infinite Mixtapes in the order nts.live lists them.
    static let all: [Station] = [
        live("1", "https://stream-relay-geo.ntslive.net/stream?client=direct"),
        live("2", "https://stream-relay-geo.ntslive.net/stream2?client=direct"),
        mixtape("poolside", "Poolside", "mixtape4", "Balearic, boogie, and sophisti-pop for poolsides, beaches and car stereos."),
        mixtape("slow-focus", "Slow Focus", "mixtape", "Meditative, relaxing and beatless: ambient, drone and ragas."),
        mixtape("low-key", "Low Key", "mixtape2", "Keeping it simple with lo-fi hip-hop and smooth R’n’B."),
        mixtape("memory-lane", "Memory Lane", "mixtape6", "Turn on, tune in, drop out."),
        mixtape("4-to-the-floor", "4 To The Floor", "mixtape5", "House and techno from past to present."),
        mixtape("island-time", "Island Time", "mixtape21", "Easy skanking: reggae, dub, and plenty more."),
        mixtape("the-tube", "The Tube", "mixtape26", "Oddball post-punk, industrial provocation, and minimal wave."),
        mixtape("sheet-music", "Sheet Music", "mixtape35", "The best of classical and contemporary composition."),
        mixtape("feelings", "Feelings", "mixtape27", "Sweet soul, gospel, boogie, and beyond."),
        mixtape("expansions", "Expansions", "mixtape3", "Jazz and its many mind-expanding variations."),
        mixtape("rap-house", "Rap House", "mixtape22", "808s and champagne."),
        mixtape("labyrinth", "Labyrinth", "mixtape31", "Enter the void."),
        mixtape("sweat", "Sweat", "mixtape24", "A new wave of international party music."),
        mixtape("otaku", "Otaku", "mixtape36", "Video game and anime soundtracks."),
        mixtape("the-pit", "The Pit", "mixtape34", "Behold the songs of the ancient metal bards."),
        mixtape("field-recordings", "Field Recordings", "mixtape23", "Natural ambience from NTS listeners around the world."),
    ]

    private static func live(_ channel: String, _ stream: String) -> Station {
        Station(id: "nts-\(channel)", name: "NTS \(channel)", kind: .live(channel: channel), stream: URL(string: stream)!, blurb: "")
    }

    private static func mixtape(_ id: String, _ name: String, _ path: String, _ blurb: String) -> Station {
        Station(id: id, name: name, kind: .mixtape, stream: URL(string: "https://stream-mixtape-geo.ntslive.net/\(path)")!, blurb: blurb)
    }
}
