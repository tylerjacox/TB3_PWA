// TB3 iOS — Spotify State (observable, mirrors StravaState pattern)

import Foundation

struct SpotifyNowPlaying: Equatable {
    let trackId: String
    let trackName: String
    let artistName: String
    let albumArtURL: String? // 64x64 image URL from Spotify API (phone)
    let albumArtURLLarge: String? // 300x300 image URL (Cast/TV)
    let isPlaying: Bool
    var isLiked: Bool
}

@Observable
final class SpotifyState {
    var isConnected = false
    var isLoading = false
    var userName: String?
    var nowPlaying: SpotifyNowPlaying?
    var needsReauth = false // Set when token scopes are insufficient

}
