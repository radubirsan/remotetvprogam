import SwiftUI
import AVKit
import AVFoundation
import WebKit

/// Side-panel rendering of the hardcoded ``TVApp`` shortcuts (Netflix, Disney+,
/// YouTube). Lives on the left of the remote, mutually exclusive with the other
/// side panels. Useful when the dynamic ``InstalledAppsSection`` probe doesn't
/// surface an app the user knows is installed — these are the bare-IDs that
/// Samsung's `applications` REST endpoint accepts directly on every modern Tizen
/// build we've tested.
///
/// Below the app shortcuts is a **Cast** group:
/// * **YouTube Cast** — a DIAL launch that opens a specific video/playlist in the
///   TV's YouTube app.
/// * **AirPlay (YouTube)** — loads the YouTube watch page in a `WKWebView`, exactly
///   like Safari. YouTube's web player resolves the page into a real video stream and
///   plays it in an HTML5 `<video>` element; tapping the AirPlay button in the player
///   controls then streams *that element* to the TV — the same thing Mac Safari does.
/// * **AirPlay (file)** — opens a real `AVPlayer` (via ``AirPlayPlayerScreen``) on a
///   direct media URL, wired for external playback. Use this for `.mp4`/`.m3u8`
///   streams you have a direct link to.
///
/// The common rule: AirPlay relays a *live media element*, never a bare web URL. A
/// standalone route picker shows the TV's idle AirPlay screen because nothing is
/// playing behind it. DIAL is the only path that opens a web URL as an *app* on the TV.
@MainActor
struct RemoteSidePanelShortcuts: View {
    let onLaunch: (String) async -> Void
    /// Casts the demo YouTube link to the TV's YouTube app via DIAL. Async so the
    /// caller can await the HTTP round-trip and surface errors.
    let onCastYouTube: () async -> Void

    /// A public, reliably-streamable demo clip. AirPlay needs a *playable media*
    /// URL (HLS/MP4), not a web page — swap this for any direct video URL to send
    /// your own content to the TV.
    static let airplayDemoURL = "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4"

    /// Drives the full-screen AirPlay player covers.
    @State private var showAirPlayFile = false
    @State private var showAirPlayYouTube = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcuts")
                .font(.title3.bold())
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                ForEach(TVApp.allCases) { app in
                    Button {
                        Task { await onLaunch(app.appID) }
                    } label: {
                        Text(app.displayName)
                            .bold()
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint(for: app))
                    .accessibilityLabel(Text("Launch \(app.displayName)"))
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            Text("Cast")
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.7))

            VStack(spacing: 8) {
                Button {
                    Task { await onCastYouTube() }
                } label: {
                    Label("YouTube Cast", systemImage: "play.rectangle.fill")
                        .bold()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel(Text("Cast YouTube video to TV"))

                // Loads the YouTube watch page in a WKWebView — same as Safari. The web
                // player resolves the stream; tap the AirPlay glyph in the video controls
                // and pick the TV to cast it, exactly like casting from Mac Safari.
                Button {
                    showAirPlayYouTube = true
                } label: {
                    Label("AirPlay (YouTube)", systemImage: "airplayvideo")
                        .bold()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .accessibilityLabel(Text("Open YouTube in a web player to AirPlay"))

                // Opens a real AVPlayer on a direct media URL, wired for external playback.
                // Inside it, tap the AirPlay glyph and pick the TV — the video then plays
                // *on the TV*. Use this for direct .mp4/.m3u8 links.
                Button {
                    showAirPlayFile = true
                } label: {
                    Label("AirPlay (file)", systemImage: "airplayvideo")
                        .bold()
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
                .accessibilityLabel(Text("Open a direct media file to AirPlay"))

                // Pick a video or photos from the library and cast them to the TV (video via
                // the player's AirPlay button; photos via Screen Mirroring).
                MediaCastButton()
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RemoteTheme.body.opacity(0.5))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .colorScheme(.dark)
        .fullScreenCover(isPresented: $showAirPlayFile) {
            if let url = URL(string: Self.airplayDemoURL) {
                AirPlayPlayerScreen(url: url)
            }
        }
        .fullScreenCover(isPresented: $showAirPlayYouTube) {
            if let url = URL(string: RemoteViewModel.youtubeCastURL) {
                WebAirPlayScreen(url: url)
            }
        }
    }

    private func tint(for app: TVApp) -> Color {
        switch app {
        case .netflix:    .red
        case .disneyPlus: .blue
        case .youtube:    .pink
        }
    }
}

/// Full-screen `AVPlayerViewController` host for the AirPlay demo. The native player
/// chrome already includes the AirPlay route button; selecting the TV streams the
/// playing video out over AirPlay. A close button dismisses (which also tears down the
/// player and ends external playback).
private struct AirPlayPlayerScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AirPlayVideoPlayer(url: url)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .padding()
            }
            .accessibilityLabel(Text("Close AirPlay player"))
        }
        .preferredColorScheme(.dark)
    }
}

/// SwiftUI wrapper around `AVPlayerViewController`, configured so the playing item can
/// hand its video to an AirPlay receiver. `allowsExternalPlayback` (plus the
/// while-external flag) is what lets the AirPlay route button push the *video* to the
/// TV rather than just mirroring a black frame. We also set the audio session to
/// `.playback` so sound isn't gated by the ringer switch and routes with the video.
private struct AirPlayVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true

        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

/// Full-screen host for the WebKit-based YouTube AirPlay path. Loads the watch page in
/// a ``YouTubeWebPlayer``; the user plays the video and AirPlays it from the player's
/// own controls. A close button dismisses (tearing down the web view ends playback).
private struct WebAirPlayScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            YouTubeWebPlayer(url: url)
                .ignoresSafeArea(edges: .bottom)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .padding()
            }
            .accessibilityLabel(Text("Close YouTube player"))
        }
        .preferredColorScheme(.dark)
    }
}

/// `WKWebView` wrapper that loads a YouTube watch page just like Safari. Inline media
/// playback is enabled so the HTML5 `<video>` element renders in-app, and
/// `allowsAirPlayForMediaPlayback` (default, set explicitly for clarity) lets that
/// element be AirPlayed to the TV — the same mechanism as casting from desktop Safari.
/// We don't require a user gesture for playback so the video can start on its own.
private struct YouTubeWebPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
