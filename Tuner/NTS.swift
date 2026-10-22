import Foundation

struct Show: Equatable, Sendable {
    let title: String
    let location: String?
    let start: Date
    let end: Date
    let artwork: URL?
}

struct Schedule: Equatable, Sendable {
    let now: Show
    let next: Show?
}

/// The public endpoint nts.live itself polls for the live channels.
enum NTS {
    static let liveURL = URL(string: "https://www.nts.live/api/v2/live")!

    /// Keyed by channel name, "1" and "2".
    static func live() async throws -> [String: Schedule] {
        var request = URLRequest(url: liveURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> [String: Schedule] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(LiveResponse.self, from: data)

        return Dictionary(uniqueKeysWithValues: response.results.map { channel in
            (channel.channelName, Schedule(now: channel.now.show, next: channel.next?.show))
        })
    }
}

private struct LiveResponse: Decodable {
    let results: [Channel]

    struct Channel: Decodable {
        let channelName: String
        let now: Broadcast
        let next: Broadcast?
    }

    struct Broadcast: Decodable {
        let broadcastTitle: String
        let startTimestamp: Date
        let endTimestamp: Date
        let embeds: Embeds

        var show: Show {
            // broadcast_title is shouted in caps; the episode name keeps the show's own casing.
            Show(
                title: embeds.details?.name ?? broadcastTitle,
                location: embeds.details?.locationLong,
                start: startTimestamp,
                end: endTimestamp,
                artwork: embeds.details?.media?.backgroundMedium
            )
        }
    }

    /// An object when NTS has episode details, an empty array when it doesn't.
    struct Embeds: Decodable {
        let details: Details?

        init(from decoder: Decoder) throws {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            details = try? container?.decodeIfPresent(Details.self, forKey: .details)
        }

        enum CodingKeys: String, CodingKey { case details }
    }

    struct Details: Decodable {
        let name: String?
        let locationLong: String?
        let media: Media?
    }

    struct Media: Decodable {
        let backgroundMedium: URL?
    }
}
