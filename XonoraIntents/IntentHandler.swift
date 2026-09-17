//
//  IntentHandler.swift
//  XonoraIntents
//
//  Siri Intents extension entry point.
//

import Intents

class IntentHandler: INExtension, INPlayMediaIntentHandling {

    override func handler(for intent: INIntent) -> Any {
        return self
    }

    // MARK: - Resolve

    func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        guard let mediaSearch = intent.mediaSearch,
              let name = mediaSearch.mediaName, !name.isEmpty else {
            completion([.unsupported()])
            return
        }

        // Map Siri's media type to INMediaItemType
        let itemType: INMediaItemType
        switch mediaSearch.mediaType {
        case .song: itemType = .song
        case .album: itemType = .album
        case .artist: itemType = .artist
        case .playlist: itemType = .playlist
        case .podcastShow: itemType = .podcastShow
        case .podcastEpisode: itemType = .podcastEpisode
        case .audioBook: itemType = .audioBook
        case .station: itemType = .station
        default: itemType = .unknown
        }

        // Build a pass-through media item with the search query as identifier
        // The main app will do the actual server search during handle
        let mediaItem = INMediaItem(
            identifier: name,
            title: name,
            type: itemType,
            artwork: nil,
            artist: mediaSearch.artistName
        )

        completion([.success(with: mediaItem)])
    }

    // MARK: - Handle

    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        // Forward to the main app for playback (needs audio session + server connection)
        completion(INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil))
    }
}
