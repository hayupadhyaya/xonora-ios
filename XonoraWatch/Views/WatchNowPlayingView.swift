//
//  WatchNowPlayingView.swift
//  XonoraWatch
//
//  Now Playing view with full-screen blurred background artwork (YouTube Music style).
//  Background fills entire screen; content stays within safe area automatically.
//
//  Scale: 44mm (224pt height) = 1.0x baseline, clamped 0.78–1.15 for 38mm–Ultra.
//

import SwiftUI
#if os(watchOS)
import WatchKit
#endif
import Combine

// MARK: - ScrollingText Helper

struct ScrollingText: View {
    let text: String
    let font: Font
    var color: Color = .white

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isScrolling = false
    @State private var scrollDone = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Invisible text to measure natural width
                Text(text)
                    .font(font)
                    .fixedSize()
                    .background(
                        GeometryReader { textGeometry in
                            Color.clear.preference(
                                key: TextWidthPreferenceKey.self,
                                value: textGeometry.size.width
                            )
                        }
                    )
                    .hidden()

                if isScrolling && !scrollDone {
                    // Scrolling phase: two copies separated by a gap
                    HStack(spacing: 40) {
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize()
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize()
                    }
                    .offset(x: offset)
                } else {
                    // Static phase: truncate with ellipsis
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: geometry.size.width, alignment: .leading)
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
            .onAppear {
                containerWidth = geometry.size.width
                maybeStartScroll()
            }
            .onPreferenceChange(TextWidthPreferenceKey.self) { width in
                textWidth = width
                maybeStartScroll()
            }
        }
        .frame(height: font == .system(size: 15, weight: .semibold) ? 20 : 16)
        .onChange(of: text) { _, _ in
            // Reset when track changes
            isScrolling = false
            scrollDone = false
            offset = 0
            textWidth = 0
        }
    }

    private func maybeStartScroll() {
        // Need both measurements before deciding
        guard containerWidth > 0, textWidth > 0 else { return }
        // Only scroll if text is actually wider than the container
        guard textWidth > containerWidth else { return }
        // Don't re-start if already running or done
        guard !isScrolling, !scrollDone else { return }

        isScrolling = true
        offset = 0

        // ~50 pt/sec feels natural; minimum 3 s so short overflows aren't a blur
        let speed: Double = 50
        let duration = max(3.0, Double(textWidth + 40) / speed)

        // Brief pause before scroll begins
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.linear(duration: duration)) {
                offset = -(textWidth + 40)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                scrollDone = true
            }
        }
    }
}

struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Main View

struct WatchNowPlayingView: View {
    @EnvironmentObject var dataProvider: WatchConnectivityProvider
    @State private var volume: Double = 0.5
    @State private var volumeTask: Task<Void, Never>? = nil
    // Two-layer crossfade using pre-loaded UIImages (no AsyncImage re-init flash)
    @State private var currentImage: UIImage? = nil
    @State private var previousImage: UIImage? = nil
    @State private var previousOpacity: Double = 0.0

    // Reference-point timer sync
    @State private var referenceServerTime: TimeInterval = 0
    @State private var referenceDate: Date = .distantPast
    @State private var displayTime: TimeInterval = 0
    @State private var timerSubscription: AnyCancellable?

    // Scale factor from device screen height (constant per device)
    private var scale: CGFloat {
        #if os(watchOS)
        let height = WKInterfaceDevice.current().screenBounds.height
        #else
        let height: CGFloat = 224
        #endif
        return min(max(height / 224, 0.78), 1.15)
    }

    var body: some View {
        ZStack {
            // Background artwork fills entire screen including corners
            backgroundArtwork
                .ignoresSafeArea(.all)

            // Dark gradient for text readability
            LinearGradient(
                colors: [
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all)

            // Content stays within safe area automatically
            VStack(spacing: 6 * scale) {
                Spacer(minLength: 0)

                if let track = dataProvider.nowPlayingState.track {
                    trackInfoSection(track: track)
                    progressSection()
                    controlsSection()
                    secondaryControlsSection()
                } else {
                    emptyStateSection()
                }

                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        #if os(watchOS)
        .digitalCrownRotation($volume, from: 0.0, through: 1.0, by: 0.05, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        #endif
        .onChange(of: volume) { _, newValue in
            volumeTask?.cancel()
            volumeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                let volumeInt = Int(newValue * 100)
                await dataProvider.sendCommand(.setVolume, payload: ["volume": "\(volumeInt)"])
                volumeTask = nil
            }
        }
        .onChange(of: dataProvider.nowPlayingState.volume) { _, newValue in
            // Only sync if user isn't actively turning the crown
            guard volumeTask == nil else { return }
            volume = Double(newValue)
        }
        .onAppear {
            volume = Double(dataProvider.nowPlayingState.volume)
            if let url = dataProvider.nowPlayingState.track
                .flatMap({ $0.imageURLString })
                .flatMap({ URL(string: $0) }) {
                Task { currentImage = await fetchImage(from: url) }
            }
            syncReferencePoint()
            updateTimerState()
        }
        .onDisappear {
            timerSubscription?.cancel()
            timerSubscription = nil
            volumeTask?.cancel()
            volumeTask = nil
        }
        .onChange(of: dataProvider.nowPlayingState.track) { _, newTrack in
            syncReferencePoint()
            guard let urlString = newTrack?.imageURLString, let newURL = URL(string: urlString) else {
                // No artwork: just fade out whatever is showing
                withAnimation(.easeInOut(duration: 0.6)) { previousOpacity = 0.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    previousImage = nil; currentImage = nil
                }
                return
            }
            Task {
                // Fetch new image first so there's no loading gap during the transition
                let newImg = await fetchImage(from: newURL)
                // Step 1: place old image on top at full opacity, swap new image in below
                await MainActor.run {
                    previousImage = currentImage
                    previousOpacity = 1.0
                    currentImage = newImg
                }
                // Step 2: next run-loop tick — now SwiftUI has rendered the 1.0 state,
                // so the animation actually has something to fade from
                try? await Task.sleep(nanoseconds: 32_000_000) // ~2 frames at 60 fps
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.9)) {
                        previousOpacity = 0.0
                    }
                }
                try? await Task.sleep(nanoseconds: 950_000_000)
                await MainActor.run { previousImage = nil }
            }
        }
        .onChange(of: dataProvider.nowPlayingState.currentTime) { _, _ in
            syncReferencePoint()
        }
        .onChange(of: dataProvider.nowPlayingState.isPlaying) { _, isPlaying in
            if !isPlaying {
                displayTime = dataProvider.nowPlayingState.currentTime
                referenceServerTime = dataProvider.nowPlayingState.currentTime
                referenceDate = Date()
            } else {
                syncReferencePoint()
            }
            updateTimerState()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func trackInfoSection(track: WatchTrackInfo) -> some View {
        VStack(spacing: 3 * scale) {
            ScrollingText(text: track.name, font: .system(size: 15 * scale, weight: .semibold))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            
            ScrollingText(text: track.artistNames, font: .system(size: 12 * scale), color: .white.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 4 * scale)
    }

    @ViewBuilder
    private func progressSection() -> some View {
        let barHeight: CGFloat = max(2, 3 * scale)

        VStack(spacing: 4 * scale) {
            // Progress bar: background track has intrinsic size,
            // overlay GeometryReader reads its exact width for the fill.
            RoundedRectangle(cornerRadius: barHeight / 2)
                .fill(Color.white.opacity(0.2))
                .frame(height: barHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: barHeight / 2)
                            .fill(Color.white)
                            .frame(width: max(0, geo.size.width * progressValue))
                    }
                }

            // Time labels
            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: 10 * scale))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                Text(formatTime(dataProvider.nowPlayingState.duration))
                    .font(.system(size: 10 * scale))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 2 * scale)
    }

    @ViewBuilder
    private func controlsSection() -> some View {
        let playSize: CGFloat = 20 * scale
        let skipSize: CGFloat = 16 * scale
        let spacing: CGFloat = 20 * scale

        #if os(watchOS)
        GlassEffectContainer(spacing: 12 * scale) {
            controlButtons(playSize: playSize, skipSize: skipSize, spacing: spacing)
        }
        .padding(.vertical, 4 * scale)
        #else
        controlButtons(playSize: playSize, skipSize: skipSize, spacing: spacing)
            .padding(.vertical, 4 * scale)
        #endif
    }

    @ViewBuilder
    private func controlButtons(playSize: CGFloat, skipSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Button {
                Task { await dataProvider.sendCommand(.previous, payload: nil) }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: skipSize))
                    .foregroundColor(.white)
                    .frame(width: 32 * scale, height: 32 * scale)
            }
            .buttonStyle(.plain)
            #if os(watchOS)
            .glassEffect(.regular.interactive(), in: .circle)
            #endif

            Button {
                Task { await dataProvider.sendCommand(.playPause, payload: nil) }
            } label: {
                Image(systemName: dataProvider.nowPlayingState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playSize))
                    .foregroundColor(.white)
                    .frame(width: 44 * scale, height: 44 * scale)
            }
            .buttonStyle(.plain)
            #if os(watchOS)
            .glassEffect(.regular.interactive(), in: .circle)
            #endif

            Button {
                Task { await dataProvider.sendCommand(.next, payload: nil) }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: skipSize))
                    .foregroundColor(.white)
                    .frame(width: 32 * scale, height: 32 * scale)
            }
            .buttonStyle(.plain)
            #if os(watchOS)
            .glassEffect(.regular.interactive(), in: .circle)
            #endif
        }
    }

    @ViewBuilder
    private func secondaryControlsSection() -> some View {
        let iconSize: CGFloat = 16 * scale
        let btnSize: CGFloat = 34 * scale
        let smallSize: CGFloat = 9 * scale

        let shuffleOn = dataProvider.nowPlayingState.shuffleEnabled
        let repeatOn  = dataProvider.nowPlayingState.repeatMode != "off"

        HStack(spacing: 6 * scale) {
            // Shuffle
            Button {
                Task { await dataProvider.sendCommand(.toggleShuffle, payload: nil) }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(shuffleOn ? .black : .white)
                    .frame(width: btnSize, height: btnSize)
                    .background(
                        Circle()
                            .fill(shuffleOn ? Color.accentColor : Color.white.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: shuffleOn)

            Spacer()

            // Player name pill — taps into Devices view
            NavigationLink(destination: WatchDevicesView()) {
                HStack(spacing: 2) {
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: smallSize))
                    if let playerName = dataProvider.nowPlayingState.activePlayerName {
                        Text(playerName)
                            .font(.system(size: smallSize))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: smallSize * 0.8))
                        .opacity(0.7)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 4 * scale)
                .background(Color.white.opacity(0.25))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Repeat
            Button {
                Task { await dataProvider.sendCommand(.cycleRepeat, payload: nil) }
            } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(repeatOn ? .black : .white)
                    .frame(width: btnSize, height: btnSize)
                    .background(
                        Circle()
                            .fill(repeatOn ? Color.accentColor : Color.white.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: repeatOn)
        }
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 2 * scale)
    }

    @ViewBuilder
    private func emptyStateSection() -> some View {
        VStack(spacing: 6 * scale) {
            Image(systemName: "music.note")
                .font(.system(size: 30 * scale))
                .foregroundColor(.white.opacity(0.5))

            Text("No Track")
                .font(.system(size: 13 * scale))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Full-screen background

    @ViewBuilder
    private var backgroundArtwork: some View {
        ZStack {
            Color.black

            // Layer 1 (bottom): incoming / current artwork
            if let img = currentImage {
                artworkLayer(image: img)
            }

            // Layer 2 (top): outgoing artwork, fades out to reveal layer below
            if let img = previousImage {
                artworkLayer(image: img)
                    .opacity(previousOpacity)
            }
        }
    }

    @ViewBuilder
    private func artworkLayer(image: UIImage) -> some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .blur(radius: 2)
                .opacity(0.5)
        }
    }

    private func fetchImage(from url: URL) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Reference-point timer sync

    private func syncReferencePoint() {
        referenceServerTime = dataProvider.nowPlayingState.currentTime
        referenceDate = Date()
        displayTime = referenceServerTime
    }

    private func updateTimerState() {
        if dataProvider.nowPlayingState.isPlaying {
            guard timerSubscription == nil else { return }
            timerSubscription = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    let elapsed = Date().timeIntervalSince(referenceDate)
                    let computed = referenceServerTime + elapsed
                    let duration = dataProvider.nowPlayingState.duration
                    displayTime = duration > 0 ? min(computed, duration) : computed
                }
        } else {
            timerSubscription?.cancel()
            timerSubscription = nil
        }
    }

    private var progressValue: Double {
        guard dataProvider.nowPlayingState.duration > 0 else { return 0 }
        return min(displayTime / dataProvider.nowPlayingState.duration, 1.0)
    }

    private var repeatIcon: String {
        switch dataProvider.nowPlayingState.repeatMode {
        case "one": return "repeat.1"
        case "all": return "repeat"
        default: return "repeat"
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Now Playing") {
    WatchNowPlayingView()
        .environmentObject(WatchConnectivityProvider.previewPlaying)
}

#Preview("Paused") {
    WatchNowPlayingView()
        .environmentObject(WatchConnectivityProvider.previewPaused)
}

#Preview("No Track") {
    WatchNowPlayingView()
        .environmentObject(WatchConnectivityProvider.previewEmpty)
}
#endif
