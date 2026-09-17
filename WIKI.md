# Xonora — User Guide

> **Archived repository.** This guide describes the original Swift-only Xonora app (v1.0.8). Development has since moved to a shared core architecture — see the top-level [README](README.md) for details. This code is retired and unsupported.

A native client for [Music Assistant](https://music-assistant.io/) for iOS, watchOS, and CarPlay.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Getting Started](#getting-started)
3. [Connecting to Your Server](#connecting-to-your-server)
4. [Generating an Access Token](#generating-an-access-token)
5. [Audio Playback & Sendspin](#audio-playback--sendspin)
6. [Player Management](#player-management)
7. [Now Playing & Queue](#now-playing--queue)
8. [Apple Watch](#apple-watch)
9. [CarPlay](#carplay)
10. [Language & Localization](#language--localization)
11. [FAQs](#faqs)
12. [Common Mistakes](#common-mistakes)
13. [Troubleshooting](#troubleshooting)
14. [Support & Feedback](#support--feedback)

---

## Requirements

- **Music Assistant server** (self-hosted) — version 2.7 or later (API schema 28+)
- **Sendspin provider** enabled in Music Assistant
- **iOS 18.0** or later (iPhone/iPad)
- **watchOS 26.2** or later (Apple Watch — requires iPhone as relay)
- Your device and server must be on the **same local network**

---

## Getting Started

1. Build and install Xonora from source (see the [README](README.md)) — this original app is no longer distributed through TestFlight or the App Store.
2. Open the app — you will be taken to the connection screen.
3. Enter your **server address** and **access token**.
4. Tap **Connect**.

That's it. Once connected, your full Music Assistant library will load automatically.

---

## Connecting to Your Server

### Server Address

The server address is the full URL of your Music Assistant instance, including the port number.

**Correct format:**
```
http://192.168.1.100:8095
```

**Common mistakes:**
- Missing `http://` — the prefix is required
- Wrong port — Music Assistant defaults to `8095`
- Using a hostname that doesn't resolve on your network (use the IP address if unsure)
- Using `https://` when your server is not configured for TLS

### Access Token

The access token authenticates the app with your server. It is **not** a username or password — it is a long string of characters generated in Music Assistant.

See [Generating an Access Token](#generating-an-access-token) below.

---

## Generating an Access Token

1. Open your Music Assistant web interface in a browser (`http://YOUR_SERVER_IP:8095`).
2. Click the **profile icon** or navigate to **Settings → Users**.
3. Select your user account.
4. Scroll down to **Long-lived access tokens**.
5. Click **Create Token**, give it a name (e.g. "Xonora"), and confirm.
6. **Copy the token immediately** — it will not be shown again.
7. Paste it into the Access Token field in Xonora.

> **Note:** If you lose the token, you can revoke it and generate a new one from the same screen.

---

## Audio Playback & Sendspin

Xonora uses the **Sendspin** audio engine for high-quality, low-latency streaming. Sendspin must be enabled in Music Assistant as a player provider.

### Enabling Sendspin in Music Assistant

1. In the Music Assistant web UI, go to **Settings → Player Providers**.
2. Find **Sendspin** and enable it.
3. A player will appear with your device name.

### Enabling Sendspin in Xonora

1. Open **Settings** (gear icon) in Xonora.
2. Scroll to the **Sendspin** section.
3. Toggle Sendspin **on**.
4. Set a **device name** — this is how the player will appear in Music Assistant.

> **Tip:** If you change the device name, make sure to select the updated player as your active device.

---

## Player Management

Xonora supports multiple Music Assistant players. You can switch between them from within the app.

### Selecting a Player

1. Tap the **device icon** in the Now Playing bar or the Now Playing tab.
2. A list of all available players will appear.
3. Tap the player you want to use.

The app will prefer your **local iOS Sendspin player** automatically when available.

### Now Playing Tab

The Now Playing tab shows:
- The currently playing track
- Which device audio is routing to
- Full playback controls and queue

If audio seems to be playing somewhere unexpected, check the Now Playing tab to see which player is active.

---

## Now Playing & Queue

- **Queue:** Tap the queue icon in the Now Playing view to see and reorder upcoming tracks.
- **Reorder:** Drag tracks to reorder them.
- **Remove:** Swipe left on a track to remove it from the queue.
- **Continue Listening:** The Home tab shows recently played items so you can pick up where you left off.

---

## Apple Watch

Xonora includes a companion watchOS app. It requires your iPhone to be nearby and connected (the Watch does not connect to the server directly).

**Controls available on Watch:**
- Play / Pause
- Next / Previous track
- Volume control
- Player switching

Data syncs automatically whenever the iPhone app is open and connected.

---

## CarPlay

Xonora supports CarPlay for in-car playback.

- Connect your iPhone to a CarPlay-compatible head unit.
- Xonora will appear in the CarPlay app list.
- You can browse your Library and control Now Playing from CarPlay.

---

## Language & Localization

Xonora supports 34 languages. You can change the app language independently from your device language.

### Changing the Language

1. Open **Settings** in Xonora.
2. Under **Personalization**, tap **Language**.
3. Select your preferred language from the list.
4. The app will update immediately.

### Supported Languages

English, German, Spanish, French, Italian, Japanese, Korean, Portuguese (Brazil), Portuguese (Portugal), Russian, Simplified Chinese, Traditional Chinese, Arabic, Hebrew, Hindi, Thai, Vietnamese, Indonesian, Malay, Dutch, Danish, Norwegian, Swedish, Finnish, Polish, Czech, Slovak, Croatian, Hungarian, Romanian, Ukrainian, Greek, Turkish, and Catalan.

Each language shows its native name and English name for easy identification.

---

## FAQs

**Q: Do I need a Music Assistant account or subscription?**
A: No. Music Assistant is self-hosted and free. You only need your own server running on your local network.

**Q: Can I use Xonora outside my home network?**
A: Only if your Music Assistant server is accessible remotely (e.g. via VPN or reverse proxy). The app connects directly to your server's IP address and port.

**Q: Why does the app seem unresponsive on first launch?**
A: The app initialises several background services on first launch. This may take a few seconds. This will be improved in a future update.

**Q: The app is slow when I type my server address or token. Is that normal?**
A: Yes, this is a known issue in the current beta. The UI may briefly lag while entering login credentials. This will be fixed in a future version.

**Q: Can I use Xonora with multiple Music Assistant servers?**
A: Currently the app connects to one server at a time. You can change the server address in Settings.

**Q: Does Xonora support Spotify / Apple Music / Tidal?**
A: Xonora itself does not handle music provider accounts. Any providers you have connected in Music Assistant (Spotify, Tidal, Apple Music, etc.) will be available through Xonora automatically.

**Q: My music library isn't showing up. What should I do?**
A: Make sure your library is indexed in Music Assistant. Go to the Music Assistant web UI and check that your music providers are connected and synced.

**Q: Can I use AirPlay with Xonora?**
A: Yes. AirPlay is supported through the standard iOS audio system when playing via the Sendspin player.

**Q: Can I change the app language?**
A: Yes. Go to Settings > Personalization > Language. You can choose from 34 languages independently of your device language.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Server address missing `http://` | Use `http://192.168.1.x:8095` — include the prefix |
| Wrong port number | Music Assistant defaults to port `8095` |
| Pasting username/password as the token | The Access Token is a long string generated in MA settings, not your login credentials |
| Token generated but not copied | Tokens are only shown once — if lost, revoke and create a new one |
| Sendspin not enabled in Music Assistant | Go to MA Settings → Player Providers and enable Sendspin |
| Device not selected as current player | Tap the device icon and select your iOS device from the player list |
| App not on same network as server | iPhone and server must be on the same local network (or server must be remotely accessible) |
| Using `https://` without TLS configured | Use `http://` unless you have explicitly set up HTTPS on your server |

---

## Troubleshooting

### Cannot connect to server

1. Confirm the server address is correct: `http://IP:8095`
2. Open `http://YOUR_IP:8095` in Safari on the same iPhone — if it doesn't load, the server is unreachable.
3. Confirm your iPhone is on the same Wi-Fi network as the server.
4. Check that no VPN is active that might block local connections.
5. Try using the server's IP address instead of a hostname.

### Audio not playing

1. Go to **Settings** in Xonora and ensure Sendspin is toggled on.
2. Confirm Sendspin is enabled as a player provider in Music Assistant.
3. Tap the device icon and verify your iOS device is selected as the active player.
4. Check the Now Playing tab to see which device audio is routing to.
5. Try changing your device name in Settings, then re-selecting the player.

### Music loads but nothing plays

- Check that the Sendspin player in Music Assistant shows your device name and is active.
- Ensure background audio permission is granted for Xonora in iOS Settings → Xonora.

### App disconnects when backgrounded

- This is normal on poor network connections. The app reconnects automatically when you return to the foreground.
- When resuming after a long pause, the app verifies the correct track is still queued and restores it if the server's queue has changed.
- Ensure the server is reachable and stable.

### Watch app not updating

- Keep the iPhone app open and connected.
- On the Watch, press the Digital Crown and relaunch Xonora.
- Ensure Bluetooth and Wi-Fi are enabled on both devices.

---

## Support & Feedback

- **This repository is archived.** Issues and pull requests against this code are not monitored.
- **Discord:** https://discord.gg/x6cWh4AjNG — support and feedback for the current Xonora app.
- **Source:** https://github.com/hayupadhyaya/xonora-ios
