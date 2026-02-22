# Music Assistant API Reference

This document lists the Music Assistant WebSocket API commands used by the Xonora iOS app.

## Connection

Connect via WebSocket to: `ws://<server>:<port>/ws`

All commands are sent as JSON with the format:
```json
{
  "message_id": "<unique_id>",
  "command": "<command_name>",
  "args": { ... }
}
```

## Players

### Get All Players
```
command: "players/all"
args: {}
returns: Player[]
```

Returns all registered players with their current state, including `current_media` and `playback_state`.

### Player Events (WebSocket)
- `player_added` - New player registered
- `player_updated` - Player state changed (includes current_media, playback_state)
- `player_removed` - Player unregistered

## Player Queues

### Get Queue Items
```
command: "player_queues/items"
args: {
  "queue_id": "<player_id>",
  "limit": 100
}
returns: QueueItem[]
```

### Get Queue State
```
command: "player_queues/get_queue"
args: {
  "queue_id": "<player_id>"
}
returns: {
  "current_index": number,
  "elapsed_time": number,
  "state": "idle" | "playing" | "paused"
}
```

### Play Media
```
command: "player_queues/play_media"
args: {
  "queue_id": "<player_id>",
  "media": ["<uri1>", "<uri2>", ...],
  "option": "play" | "replace" | "next" | "replace_next" | "add"
}
```

### Play/Pause
```
command: "player_queues/play_pause"
args: { "queue_id": "<player_id>" }
```

### Next Track
```
command: "player_queues/next"
args: { "queue_id": "<player_id>" }
```

### Previous Track
```
command: "player_queues/previous"
args: { "queue_id": "<player_id>" }
```

### Stop
```
command: "player_queues/stop"
args: { "queue_id": "<player_id>" }
```

### Seek
```
command: "player_queues/seek"
args: {
  "queue_id": "<player_id>",
  "position": <seconds>
}
```

### Set Volume
```
command: "players/cmd/volume_set"
args: {
  "player_id": "<player_id>",
  "volume_level": <0-100>
}
```

### Shuffle
```
command: "player_queues/shuffle"
args: {
  "queue_id": "<player_id>",
  "shuffle_enabled": true | false
}
```

### Repeat
```
command: "player_queues/repeat"
args: {
  "queue_id": "<player_id>",
  "repeat_mode": "off" | "one" | "all"
}
```

### Queue Events (WebSocket)
- `queue_updated` - Queue state changed
- `queue_items_updated` - Queue items changed
- `queue_time_updated` - Playback position update (frequent, lightweight)

## Music Library

### Get Albums
```
command: "music/albums/library_items"
args: {}
returns: Album[]
```

### Get Artists
```
command: "music/artists/library_items"
args: {}
returns: Artist[]
```

### Get Tracks
```
command: "music/tracks/library_items"
args: {}
returns: Track[]
```

### Get Playlists
```
command: "music/playlists/library_items"
args: {}
returns: Playlist[]
```

### Get Album Tracks
```
command: "music/albums/album_tracks"
args: {
  "item_id": "<album_id>",
  "provider_instance_id_or_domain": "<provider>"
}
returns: Track[]
```

### Get Playlist Tracks
```
command: "music/playlists/playlist_tracks"
args: {
  "item_id": "<playlist_id>",
  "provider_instance_id_or_domain": "<provider>"
}
returns: Track[]
```

### Get Artist Albums
```
command: "music/artists/artist_albums"
args: {
  "item_id": "<artist_id>",
  "provider_instance_id_or_domain": "<provider>"
}
returns: Album[]
```

### Get Artist Tracks
```
command: "music/artists/artist_tracks"
args: {
  "item_id": "<artist_id>",
  "provider_instance_id_or_domain": "<provider>"
}
returns: Track[]
```

### Recently Played Items
```
command: "music/recently_played_items"
args: {
  "limit": 20,
  "media_types": ["track", "album", "playlist"]  // optional filter
}
returns: RecentlyPlayedItem[]
```

Returns recently played items across all media types.

### Search
```
command: "music/search"
args: {
  "search_query": "<query>",
  "media_types": ["track", "album", "artist", "playlist"],
  "limit": 25
}
returns: {
  "tracks": Track[],
  "albums": Album[],
  "artists": Artist[],
  "playlists": Playlist[]
}
```

## Favorites

### Add to Favorites
```
command: "music/favorites/add_item"
args: { "item": "<uri>" }
```

### Remove from Favorites
```
command: "music/favorites/remove_item"
args: { "item": "<uri>" }
```

## Data Types

### Player
```typescript
{
  player_id: string;
  provider: string;
  name: string;
  type: string;
  available: boolean;
  playback_state?: "idle" | "playing" | "paused";
  volume_level?: number;
  current_media?: {
    title?: string;
    artist?: string;
    album?: string;
    image_url?: string;
    duration?: number;
    uri?: string;
  };
  active_source?: string;  // queue_id
}
```

### Track
```typescript
{
  item_id: string;
  provider: string;
  name: string;
  uri: string;
  duration?: number;
  track_number?: number;
  disc_number?: number;
  image?: string;
  artists?: Artist[];
  album?: Album;
  favorite?: boolean;
}
```

### Album
```typescript
{
  item_id: string;
  provider: string;
  name: string;
  uri: string;
  image?: string;
  artists?: Artist[];
  year?: number;
  favorite?: boolean;
}
```

### Artist
```typescript
{
  item_id: string;
  provider: string;
  name: string;
  uri: string;
  image?: string;
  favorite?: boolean;
}
```

### Playlist
```typescript
{
  item_id: string;
  provider: string;
  name: string;
  uri: string;
  image?: string;
  owner?: string;
  favorite?: boolean;
}
```

### RecentlyPlayedItem
```typescript
{
  item_id: string;
  provider: string;
  name: string;
  media_type: "track" | "album" | "playlist" | "artist";
  uri: string;
  image?: string;
  artist?: string;
  album?: string;
  duration?: number;
}
```

## Provider URIs

URIs follow the pattern: `<provider>://<media_type>/<item_id>`

Examples:
- `apple_music://track/123456`
- `spotify://album/abc123`
- `library://playlist/my-playlist`

The provider can be extracted from the URI scheme to show provider-specific icons.

## Common Providers
- `apple_music` - Apple Music
- `spotify` - Spotify
- `tidal` - Tidal
- `qobuz` - Qobuz
- `library` - Local library
- `file` - Local files
- `url` - URL streams

---

*This documentation is based on the Music Assistant frontend implementation and may not be exhaustive. See the [Music Assistant GitHub](https://github.com/music-assistant) for more details.*
