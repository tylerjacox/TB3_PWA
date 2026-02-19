// TB3 iOS — Now Playing View (compact Spotify bar for session screen)

import SwiftUI

struct NowPlayingView: View {
    let nowPlaying: SpotifyNowPlaying?
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onToggleLike: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Album art — use CachedAlbumArt to avoid re-fetching on every re-render
            CachedAlbumArt(urlString: nowPlaying?.albumArtURL)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying?.trackName ?? "")
                    .font(.subheadline.bold())
                    .lineLimit(1)

                Text(nowPlaying?.artistName ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.tb3Muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Like button
            Button { onToggleLike() } label: {
                Image(systemName: nowPlaying?.isLiked == true ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(nowPlaying?.isLiked == true ? Color(red: 0.12, green: 0.84, blue: 0.38) : Color.tb3Muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nowPlaying?.isLiked == true ? "Unlike song" : "Like song")

            // Playback controls
            HStack(spacing: 0) {
                Button { onPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                        .foregroundStyle(Color.tb3Text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous track")

                Button { onPlayPause() } label: {
                    Image(systemName: nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .foregroundStyle(Color.tb3Text)
                        .frame(width: 48, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(nowPlaying?.isPlaying == true ? "Pause" : "Play")

                Button { onNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundStyle(Color.tb3Text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next track")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

/// Caches downloaded album art in memory to avoid re-fetching on every SwiftUI re-render.
/// AsyncImage re-downloads on each view identity change; this caches by URL.
private struct CachedAlbumArt: View {
    let urlString: String?

    @State private var image: UIImage?
    @State private var loadedURL: String?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.tb3Card)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(Color.tb3Muted)
                    }
            }
        }
        .onChange(of: urlString) { _, newURL in
            loadImageIfNeeded(newURL)
        }
        .onAppear {
            loadImageIfNeeded(urlString)
        }
    }

    private func loadImageIfNeeded(_ url: String?) {
        guard let url, url != loadedURL else { return }
        guard let imageURL = URL(string: url) else { return }

        Task.detached {
            guard let (data, _) = try? await URLSession.shared.data(from: imageURL),
                  let uiImage = UIImage(data: data) else { return }
            await MainActor.run {
                self.image = uiImage
                self.loadedURL = url
            }
        }
    }
}
