# Add Spotify Integration — Search, Playback & Account Connection

## Overview
Connect your PlayMe app to Spotify so users can search songs from Spotify's catalog, play 30-second previews (or full songs for Premium users), and manage their Spotify connection.

---

## Features

- **Connect Spotify account** during onboarding or from Profile settings
- **Search songs via Spotify** when connected — falls back to iTunes search when not connected (seamless, no toggle)
- **30-second song previews** play inside the app for all users
- **Full song playback with scrubbing** for Spotify Premium users (requires Spotify app installed on device)
- **Open in Spotify** button on every song to jump to the full track in the Spotify app
- **Disconnect Spotify** from Profile settings
- **Secure token storage** — login tokens saved in Keychain, auto-refreshed when expired

---

## Design

- **Spotify connect button** uses Spotify's green brand color with the Spotify logo icon
- **Now Playing mini-bar** appears at the bottom of the screen when a song preview is playing — shows album art, song title, play/pause, and a progress indicator
- **Full playback view** slides up from the mini-bar with large album art, scrubber, play/pause/skip controls — dark theme matching the app's existing aesthetic
- **Connected badge** shows on Profile when Spotify is linked (green dot + "Spotify Connected")
- Song search results show a small Spotify icon next to results when searching via Spotify

---

## Screens & Changes

### Onboarding (new step after name/username)
- New optional "Connect Spotify" step with a branded green button
- "Skip for now" option to proceed without connecting
- Brief explanation: "Connect Spotify to search millions of songs and play full tracks"

### Send Song Sheet (updated)
- Search now hits Spotify Web API when connected, iTunes when not
- Each song row gets a small play/pause button for 30-sec preview
- Song results include Spotify URI for deep linking

### Home Feed / Song Cards (updated)
- Tap album art to play preview
- "Open in Spotify" button on each card
- Now Playing mini-bar appears at bottom when audio is playing

### Profile (updated)
- New "Music Service" section showing connection status
- "Connect Spotify" or "Disconnect Spotify" button
- Shows Spotify display name when connected

### Now Playing Bar (new)
- Floating mini-bar above the tab bar
- Shows current song art, title, artist
- Play/pause button and progress bar
- Tap to expand to full player view

### Full Player View (new)
- Large album art with blurred background
- Song title, artist name
- Progress scrubber (full scrubbing for Premium, fixed 30-sec for free)
- Play/pause, previous, next controls
- "Open in Spotify" button

---

## Technical Approach (high level)

- Uses **Spotify's official iOS Auth SDK** for secure login with PKCE (no backend server needed)
- Uses **Spotify Web API** for searching songs and getting track metadata
- Uses **AVPlayer** for 30-second preview playback (works for all users, even in simulator)
- Uses **Spotify App Remote SDK** for full Premium playback when the Spotify app is installed on device
- Tokens stored securely in Keychain with automatic refresh
- URL scheme `playme://spotify-callback` handles the redirect after login
