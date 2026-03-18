# Play Me — MVP: Send Songs to Friends' Home Screens

## Features

- **Onboarding flow**: Splash screen with "PLAY ME" branding → phone number + 6-digit code verification → enter first name + choose username → widget setup instructions (skippable)
- **Song feed**: Full-screen vertical swipeable cards showing received songs — sender name, large album art, song title & artist, optional note, and an "Open in Spotify / Apple Music" button (shows toast for now)
- **Send a song**: Search from a built-in list of 15 popular songs with album art → pick a friend by username (instant mutual connection, no accept flow) → add an optional note (150 chars) → send with a "Sent!" animation
- **Home screen widget**: Small widget showing the latest received song's album art as full-bleed background, sender initials badge, and note preview — tapping opens the app to that exact song card
- **Profile screen**: Shows name, @username, and simple lists of songs sent & received
- **Bottom tab bar**: Home (feed), Send, Profile — three tabs
- **All data is mock/local for this MVP** — 15 hardcoded songs with real album art URLs, no real backend or music service integration

## Design

- **Dark cinematic aesthetic** inspired by your screenshots — pure black backgrounds, warm album art as the dominant visual, minimal chrome
- Organic blob/gradient shapes on onboarding screens for visual interest (matching the dark amoeba-like shapes in your mockups)
- Typography: clean SF Pro with bold weights for titles, lighter weights for supporting text — white on black
- Song cards fill the entire screen with large album art front and center
- Muted accent color (warm rose/salmon) for action buttons like "Share" and "Send", matching the screenshots
- Haptic feedback on send, swipe, and key interactions
- Spring animations for card transitions and the "Sent!" confirmation
- Widget uses the song's album art as a full-bleed background with a dark gradient overlay for text legibility

## Screens

1. **Splash Screen** — "PLAY ME" logo centered on a dark background with floating album art thumbnails and a "CONTINUE" button at the bottom
2. **Phone Entry** — Dark screen with a subtle organic shape, "What's your phone number?" prompt, phone input field with a next arrow button
3. **OTP Verification** — 6-digit code entry (auto-advances), dark background
4. **Name & Username** — Two sequential fields: first name, then username with availability indicator
5. **Widget Instructions** — Illustrated steps showing how to add the widget to the home screen, with a "Done" / skip option
6. **Home Feed** — Full-screen vertical paging feed of received song cards (swipe up/down); each card has sender label, album art, song info, note, and action buttons; empty state if no songs yet
7. **Send Song Sheet** — Modal with search bar, list of songs with album art + "SHARE" button → transitions to friend selector with note field → "Send" button
8. **Profile** — Avatar initials circle, name, @username, and two sections listing sent and received songs

## App Icon

- Dark background with a subtle warm gradient, featuring a play button or music note symbol in white/cream — clean and moody to match the app's dark aesthetic

