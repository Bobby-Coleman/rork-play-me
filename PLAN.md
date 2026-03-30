# Step 1: Spotify Login on the Welcome Screen

This is **Step 1 only** — we'll build and test before moving to the next step.

---

**What changes:**

- **Splash screen button** becomes "Connect with Spotify" with a Spotify-green accent and the Spotify icon feel
- Tapping it opens Spotify's login page in the system browser (Safari)
- After the user approves in Spotify, they're redirected back to PlayMe via the `playme://spotify-callback` URL
- The app receives an access token from Spotify securely (PKCE flow — no secrets stored in the app)

**New pieces:**

- A **Spotify Auth Service** that handles the secure login handshake (generating a code verifier, opening the browser, exchanging the callback code for a token)
- The app registers the custom URL `playme://spotify-callback` so iOS knows to send the user back to PlayMe after Spotify login
- The app entry point listens for that callback URL and passes it to the auth service

**Onboarding flow after this step:**

1. Splash → "Connect with Spotify" button
2. Opens Spotify login in browser → user approves → returns to app
3. Straight to **username picker** (skipping name entry — no auto-fill of name/profile picture)
4. Widget instructions → Done

**What stays the same:**
- The splash screen visual design (album art floating, PLAY ME title)
- The username picker screen
- The widget instructions screen
- Everything after onboarding (home feed, send, profile)

**What gets removed:**
- Phone number entry screen
- OTP verification screen
- First name entry step (from NameUsernameView)
