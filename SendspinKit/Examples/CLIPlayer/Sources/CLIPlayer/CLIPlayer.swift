// ABOUTME: Example CLI player demonstrating SendspinKit usage
// ABOUTME: Connects to a Sendspin server and plays synchronized audio

import Foundation
import SendspinKit

/// Simple CLI player for Sendspin Protocol
final class CLIPlayer {
    private var client: SendspinClient?
    private var eventTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private let display = StatusDisplay()

    @MainActor
    func run(serverURL: String, clientName: String, useTUI: Bool = true) async throws {
        // Simple startup banner before TUI takes over
        print("🎵 Sendspin CLI Player")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("Initializing...")

        // Parse URL
        guard let url = URL(string: serverURL) else {
            print("❌ Invalid server URL: \(serverURL)")
            throw CLIPlayerError.invalidURL
        }

        // Create player configuration
        // Advertise support for PCM, Opus, and FLAC formats
        let config = PlayerConfiguration(
            bufferCapacity: 2_097_152, // 2MB buffer
            supportedFormats: [
                // Hi-res PCM formats (24-bit)
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 192_000, bitDepth: 24),
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 176_400, bitDepth: 24),
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 96_000, bitDepth: 24),
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 88_200, bitDepth: 24),
                // Standard PCM formats (16-bit)
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 48_000, bitDepth: 16),
                AudioFormatSpec(codec: .pcm, channels: 2, sampleRate: 44_100, bitDepth: 16),
                // Compressed formats - validated and working
                AudioFormatSpec(codec: .opus, channels: 2, sampleRate: 48_000, bitDepth: 16),
                AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 48_000, bitDepth: 16),
                AudioFormatSpec(codec: .flac, channels: 2, sampleRate: 44_100, bitDepth: 16)
            ]
        )

        // Create client
        let client = SendspinClient(
            clientId: UUID().uuidString,
            name: clientName,
            roles: [.player, .metadata],
            playerConfig: config
        )
        self.client = client

        // Start event monitoring
        eventTask = Task {
            await monitorEvents(client: client, useTUI: useTUI)
        }

        // Start stats monitoring
        statsTask = Task {
            await monitorStats(client: client)
        }

        // Connect to server
        try await client.connect(to: url)

        // Small delay to let initial messages settle
        try? await Task.sleep(for: .milliseconds(500))

        if useTUI {
            // Start TUI
            await display.start()

            // Run command loop on background thread to avoid blocking MainActor
            let commandTask = Task.detached { [display] in
                await CLIPlayer.runCommandLoopStatic(client: client, display: display)
            }
            await commandTask.value

            // Clean up TUI
            await display.stop()
        } else {
            // No TUI mode - just wait forever and log events
            print("✅ Connected! Logging mode (press Ctrl-C to exit)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            // Wait forever (sleep in a loop to avoid Duration overflow)
            while true {
                try? await Task.sleep(for: .seconds(3600)) // 1 hour at a time
            }
        }
    }

    @MainActor
    private func monitorEvents(client: SendspinClient, useTUI: Bool) async {
        for await event in client.events {
            switch event {
            case let .serverConnected(info):
                if useTUI {
                    await display.updateServer(name: info.name)
                } else {
                    print("[EVENT] Server connected: \(info.name) (v\(info.version))")
                }

            case let .streamStarted(format):
                let formatStr = "\(format.codec.rawValue) \(format.sampleRate)Hz " +
                    "\(format.channels)ch \(format.bitDepth)bit"
                if useTUI {
                    await display.updateStream(format: formatStr)
                } else {
                    print("[EVENT] Stream started: \(formatStr)")
                }

            case .streamEnded:
                if useTUI {
                    await display.updateStream(format: "No stream")
                } else {
                    print("[EVENT] Stream ended")
                }

            case let .groupUpdated(info):
                if !useTUI {
                    print("[EVENT] Group updated: \(info.groupName) (\(info.playbackState ?? "unknown"))")
                }

            case let .metadataReceived(metadata):
                if useTUI {
                    await display.updateMetadata(
                        title: metadata.title,
                        artist: metadata.artist,
                        album: metadata.album,
                        artworkUrl: metadata.artworkUrl
                    )
                } else {
                    print("[METADATA] Track: \(metadata.title ?? "unknown")")
                    print("[METADATA] Artist: \(metadata.artist ?? "unknown")")
                    print("[METADATA] Album: \(metadata.album ?? "unknown")")
                    if let duration = metadata.duration {
                        print("[METADATA] Duration: \(duration)s")
                    }
                    if let artworkUrl = metadata.artworkUrl {
                        print("[METADATA] Artwork URL: \(artworkUrl)")
                    }
                }

            case let .artworkReceived(channel, data):
                if !useTUI {
                    print("[EVENT] Artwork received on channel \(channel): \(data.count) bytes")
                }

            case let .visualizerData(data):
                if !useTUI {
                    print("[EVENT] Visualizer data: \(data.count) bytes")
                }

            case let .error(message):
                if !useTUI {
                    print("[ERROR] \(message)")
                }
            }
        }
    }

    @MainActor
    private func monitorStats(client _: SendspinClient) async {
        while !Task.isCancelled {
            // Update volume from client
            // Note: Would need to expose these as observable properties
            // For now, we'll update them from command loop

            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private nonisolated static func runCommandLoopStatic(client: SendspinClient, display: StatusDisplay) async {
        while let line = readLine() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            let parts = line.split(separator: " ")
            guard let command = parts.first else { continue }

            switch command.lowercased() {
            case "q", "quit", "exit":
                await client.disconnect()
                return

            case "v", "volume":
                guard parts.count > 1, let volume = Float(parts[1]) else {
                    continue
                }
                await client.setVolume(volume / 100.0)
                await display.updateVolume(Int(volume), muted: false)

            case "m", "mute":
                await client.setMute(true)
                await display.updateVolume(100, muted: true)

            case "u", "unmute":
                await client.setMute(false)
                await display.updateVolume(100, muted: false)

            default:
                break // Ignore unknown commands in TUI mode
            }
        }
    }

    deinit {
        eventTask?.cancel()
        // Disconnect client on cleanup
        Task { @MainActor [weak client] in
            await client?.disconnect()
        }
    }
}

enum CLIPlayerError: Error {
    case invalidURL
}

// MARK: - Terminal UI

/// ANSI terminal control codes
enum ANSI {
    static let clearScreen = "\u{001B}[2J"
    static let home = "\u{001B}[H"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"
    static let saveCursor = "\u{001B}[s"
    static let restoreCursor = "\u{001B}[u"

    // Colors
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let red = "\u{001B}[31m"

    static func moveTo(row: Int, col: Int) -> String {
        return "\u{001B}[\(row);\(col)H"
    }
}

/// Live-updating status display for the CLI player
actor StatusDisplay {
    private var displayTask: Task<Void, Never>?
    private var isRunning = false

    // State
    private var serverName: String = "Not connected"
    private var streamFormat: String = "No stream"
    private var trackTitle: String?
    private var trackArtist: String?
    private var trackAlbum: String?
    private var trackArtworkUrl: String?
    private var clockOffset: Int64 = 0
    private var clockRTT: Int64 = 0
    private var clockQuality: String = "lost"
    private var chunksReceived: Int = 0
    private var chunksPlayed: Int = 0
    private var chunksDropped: Int = 0
    private var bufferMs: Double = 0.0
    private var volume: Int = 100
    private var isMuted: Bool = false
    private var uptime: TimeInterval = 0
    private let startTime = Date()

    init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Hide cursor and clear screen
        print(ANSI.hideCursor, terminator: "")
        print(ANSI.clearScreen, terminator: "")
        fflush(stdout)

        displayTask = Task {
            while !Task.isCancelled && isRunning {
                await render()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        isRunning = false
        displayTask?.cancel()
        displayTask = nil

        // Show cursor
        print(ANSI.showCursor, terminator: "")
        fflush(stdout)
    }

    // Update methods
    func updateServer(name: String) {
        serverName = name
    }

    func updateStream(format: String) {
        streamFormat = format
    }

    func updateClock(offset: Int64, rtt: Int64, quality: String) {
        clockOffset = offset
        clockRTT = rtt
        clockQuality = quality
    }

    func updateStats(received: Int, played: Int, dropped: Int, bufferMs: Double) {
        chunksReceived = received
        chunksPlayed = played
        chunksDropped = dropped
        self.bufferMs = bufferMs
    }

    func updateVolume(_ vol: Int, muted: Bool) {
        volume = vol
        isMuted = muted
    }

    func updateMetadata(title: String?, artist: String?, album: String?, artworkUrl: String?) {
        trackTitle = title
        trackArtist = artist
        trackAlbum = album
        trackArtworkUrl = artworkUrl
    }

    private func render() {
        uptime = Date().timeIntervalSince(startTime)

        var output = ANSI.home

        // Header
        output += "\(ANSI.bold)\(ANSI.cyan)"
        output += "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n"
        output += "┃                      🎵 SENDSPIN CLI PLAYER 🎵                          ┃\n"
        output += "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n"
        output += ANSI.reset
        output += "\n"

        // Connection info
        output += "\(ANSI.bold)CONNECTION\(ANSI.reset)\n"
        output += "  Server:  \(ANSI.green)\(serverName)\(ANSI.reset)\n"
        output += "  Uptime:  \(formatDuration(uptime))\n"
        output += "\n"

        // Stream info
        output += "\(ANSI.bold)STREAM\(ANSI.reset)\n"
        output += "  Format:  \(ANSI.blue)\(streamFormat)\(ANSI.reset)\n"
        if let title = trackTitle {
            output += "  Track:   \(ANSI.magenta)\(title)\(ANSI.reset)\n"
        }
        if let artist = trackArtist {
            output += "  Artist:  \(artist)\n"
        }
        if let album = trackAlbum {
            output += "  Album:   \(album)\n"
        }
        if let artworkUrl = trackArtworkUrl {
            output += "  Artwork: \(ANSI.dim)\(artworkUrl)\(ANSI.reset)\n"
        }
        output += "\n"

        // Clock sync
        let qualityColor = clockQuality == "good" ? ANSI.green : (clockQuality == "degraded" ? ANSI.yellow : ANSI.red)
        output += "\(ANSI.bold)CLOCK SYNC\(ANSI.reset)\n"
        output += "  Offset:  \(formatMicroseconds(clockOffset))\n"
        output += "  RTT:     \(formatMicroseconds(clockRTT))\n"
        output += "  Quality: \(qualityColor)\(clockQuality)\(ANSI.reset)\n"
        output += "\n"

        // Playback stats
        output += "\(ANSI.bold)PLAYBACK\(ANSI.reset)\n"
        output += "  Received: \(ANSI.cyan)\(chunksReceived)\(ANSI.reset) chunks\n"
        output += "  Played:   \(ANSI.green)\(chunksPlayed)\(ANSI.reset) chunks\n"
        output += "  Dropped:  \(chunksDropped > 0 ? ANSI.red : ANSI.dim)\(chunksDropped)\(ANSI.reset) chunks\n"
        output += "  Buffer:   \(formatBuffer(bufferMs))\n"
        output += "\n"

        // Volume
        output += "\(ANSI.bold)AUDIO\(ANSI.reset)\n"
        let volumeBar = makeVolumeBar(volume: volume, muted: isMuted)
        output += "  Volume:  \(volumeBar)\n"
        output += "\n"

        // Commands
        output += "\(ANSI.dim)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\(ANSI.reset)\n"
        output += "\(ANSI.dim)Commands: [v <0-100>] volume  [m] mute  [u] unmute  [q] quit\(ANSI.reset)\n"
        output += "\(ANSI.dim)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\(ANSI.reset)\n"
        output += "> "

        print(output, terminator: "")
        fflush(stdout)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    private func formatMicroseconds(_ microseconds: Int64) -> String {
        let absMicroseconds = abs(microseconds)

        if absMicroseconds < 1000 {
            return "\(microseconds)μs"
        } else if absMicroseconds < 1_000_000 {
            let milliseconds = Double(microseconds) / 1000.0
            return String(format: "%.1fms", milliseconds)
        } else {
            let seconds = Double(microseconds) / 1_000_000.0
            return String(format: "%.2fs", seconds)
        }
    }

    private func formatBuffer(_ milliseconds: Double) -> String {
        let color = milliseconds < 50 ? ANSI.red : (milliseconds < 100 ? ANSI.yellow : ANSI.green)
        return "\(color)\(String(format: "%.1fms", milliseconds))\(ANSI.reset)"
    }

    private func makeVolumeBar(volume: Int, muted: Bool) -> String {
        if muted {
            return "\(ANSI.red)🔇 MUTED\(ANSI.reset)"
        }

        let barWidth = 20
        let filled = (volume * barWidth) / 100
        let empty = barWidth - filled

        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: empty)
        let color = volume > 80 ? ANSI.green : (volume > 40 ? ANSI.yellow : ANSI.red)

        return "\(color)\(bar)\(ANSI.reset) \(volume)%"
    }
}
