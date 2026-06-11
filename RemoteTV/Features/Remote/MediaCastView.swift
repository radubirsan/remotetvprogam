import SwiftUI
import AVKit
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

/// "Cast Photo / Video" entry point for the Shortcuts panel. Picks media from the photo
/// library and routes it to the right viewer:
///   * **Video** → an `AVPlayerViewController` wired for external playback, so the player's
///     AirPlay button streams the video to the TV. Clean, one-tap.
///   * **Photo(s)** → a chrome-free full-screen swipeable viewer. iOS has no public API to
///     "AirPlay a still photo", so the path is **Screen Mirroring**: the viewer renders the
///     current photo onto the TV's external screen (so the TV shows just the photo, not the
///     phone UI) while the phone keeps the swipe controls. With mirroring off it still looks
///     clean — it's a black, status-bar-free full-screen photo.
@MainActor
struct MediaCastButton: View {
    @State private var showPicker = false
    @State private var videoURL: URL?
    @State private var images: [UIImage] = []
    @State private var showVideo = false
    @State private var showPhotos = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Label("Cast Photo / Video", systemImage: "photo.on.rectangle.angled")
                .bold()
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.purple)
        .accessibilityLabel(Text("Cast a photo or video from your phone"))
        // Stash the picked media, then dismiss the picker. The viewer is presented from the
        // sheet's `onDismiss` so we never present a cover while the sheet is still dismissing.
        .sheet(isPresented: $showPicker, onDismiss: presentPicked) {
            MediaPicker { pickedImages, pickedVideo in
                // A video wins if present (you can't watch a video and a slideshow at once);
                // otherwise show whatever photos were chosen.
                videoURL = pickedVideo
                images = pickedVideo == nil ? pickedImages : []
                showPicker = false
            }
        }
        .fullScreenCover(isPresented: $showVideo) {
            if let videoURL { VideoCastScreen(url: videoURL) }
        }
        .fullScreenCover(isPresented: $showPhotos) {
            PhotoCastScreen(images: images)
        }
    }

    private func presentPicked() {
        if videoURL != nil {
            showVideo = true
        } else if !images.isEmpty {
            showPhotos = true
        }
    }
}

// MARK: - Picker

/// `PHPickerViewController` wrapper. Loads images as `Data` (Sendable — sidesteps `UIImage`
/// concurrency issues) and copies any chosen video out of its temporary URL before it's reaped.
private struct MediaPicker: UIViewControllerRepresentable {
    let onComplete: ([UIImage], URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 0   // allow multiple photos
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: ([UIImage], URL?) -> Void
        init(onComplete: @escaping ([UIImage], URL?) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Don't dismiss imperatively — the `.sheet(isPresented:)` binding owns dismissal.
            guard !results.isEmpty else { onComplete([], nil); return }
            let providers = results.map(\.itemProvider)
            Task {
                var imageDatas: [Data] = []
                var videoURL: URL?
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier), videoURL == nil {
                        videoURL = await Self.loadVideo(provider)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        if let data = await Self.loadImageData(provider) { imageDatas.append(data) }
                    }
                }
                let images = imageDatas.compactMap { UIImage(data: $0) }
                let resolvedVideo = videoURL
                await MainActor.run { self.onComplete(images, resolvedVideo) }
            }
        }

        private static func loadImageData(_ provider: NSItemProvider) async -> Data? {
            await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    cont.resume(returning: data)
                }
            }
        }

        private static func loadVideo(_ provider: NSItemProvider) async -> URL? {
            await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    guard let url else { cont.resume(returning: nil); return }
                    // The provided URL is deleted when this closure returns, so copy it out.
                    let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                    try? FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: FileManager.default.fileExists(atPath: dest.path) ? dest : nil)
                }
            }
        }
    }
}

// MARK: - Video

/// Full-screen `AVPlayerViewController` host with external playback enabled, so the player's
/// own AirPlay button can push the video to the TV.
private struct VideoCastScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AirPlayVideoPlayer(url: url).ignoresSafeArea()
            CloseButton { dismiss() }
        }
        .preferredColorScheme(.dark)
    }
}

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
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

// MARK: - Photos

/// Chrome-free swipeable full-screen photo viewer. Drives ``ExternalDisplayController`` so the
/// current photo is shown on the TV's external screen when Screen Mirroring is on.
private struct PhotoCastScreen: View {
    let images: [UIImage]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var external = ExternalDisplayController()
    @State private var showRoutePicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    statusPill
                    Spacer()
                    AirPlayRoutePicker().frame(width: 40, height: 40)
                    CloseButton { dismiss() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                if !external.isActive {
                    Text("Open Control Center → **Screen Mirroring** to show this on your TV.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 28)
                }
            }
        }
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            external.start()
            external.update(image: images.indices.contains(index) ? images[index] : nil)
        }
        .onDisappear { external.stop() }
        .onChange(of: index) { _, newIndex in
            external.update(image: images.indices.contains(newIndex) ? images[newIndex] : nil)
        }
    }

    private var statusPill: some View {
        Label(external.isActive ? "On TV" : "Not on TV",
              systemImage: external.isActive ? "tv.fill" : "tv")
            .font(.caption.bold())
            .foregroundStyle(external.isActive ? .green : .white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
    }
}

// MARK: - External display

/// Manages a `UIWindow` on the TV's external screen (present while Screen Mirroring is on) so
/// the app can show *its own* full-screen photo there instead of a mirror of the phone UI.
/// Best-effort: if the OS won't hand us a usable external window, plain mirroring still shows
/// the chrome-free viewer, so the user always sees a full-screen photo on the TV.
@MainActor
@Observable
final class ExternalDisplayController {
    private(set) var isActive = false
    private var window: UIWindow?
    private var image: UIImage?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    func start() {
        attachIfPossible()
        connectObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.didConnectNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.attachIfPossible() }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScreen.didDisconnectNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.detach() }
        }
    }

    func stop() {
        [connectObserver, disconnectObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
        connectObserver = nil
        disconnectObserver = nil
        detach()
    }

    func update(image: UIImage?) {
        self.image = image
        if let host = window?.rootViewController as? UIHostingController<ExternalPhotoView> {
            host.rootView = ExternalPhotoView(image: image)
        }
    }

    private func externalScreen() -> UIScreen? {
        UIScreen.screens.first { $0 !== UIScreen.main }
    }

    private func externalWindowScene(for screen: UIScreen) -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.screen === screen }
    }

    private func attachIfPossible() {
        guard window == nil, let screen = externalScreen() else { return }
        let host = UIHostingController(rootView: ExternalPhotoView(image: image))
        host.view.backgroundColor = .black

        let externalWindow: UIWindow
        if let scene = externalWindowScene(for: screen) {
            externalWindow = UIWindow(windowScene: scene)
        } else {
            // No dedicated scene (the common case without a scene manifest) — fall back to the
            // screen-bound window. Deprecated but still functional for external displays.
            externalWindow = UIWindow(frame: screen.bounds)
            externalWindow.screen = screen
        }
        externalWindow.rootViewController = host
        externalWindow.isHidden = false
        window = externalWindow
        isActive = true
    }

    private func detach() {
        window?.isHidden = true
        window = nil
        isActive = false
    }
}

/// What renders on the TV's external screen: the photo, scaled to fit, on black.
private struct ExternalPhotoView: View {
    let image: UIImage?
    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shared bits

/// The system AirPlay route button — a quick way into the AirPlay picker. (For photos the
/// reliable route is Control Center → Screen Mirroring; this is a convenience.)
private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor.systemBlue
        view.prioritizesVideoDevices = true
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

private struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.45))
                .padding(6)
        }
        .accessibilityLabel(Text("Close"))
    }
}
