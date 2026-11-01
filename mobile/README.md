# VidShare Mobile

Flutter starter for the VidShare Android and iOS app.

## Run locally

1. Install Flutter stable and Android Studio (for Android).
2. From this directory run:

```bash
flutter pub get
flutter run
```

For iOS builds, use macOS with Xcode.

## Current status

This commit adds the original VidShare mobile shell and navigation only.
The feed, existing-account sign-in, video playback, upload, subscriptions,
and library are not connected yet.

## Important integration requirement

The existing VidShare server currently contains a Flask session-based login
and SQLite-oriented data layer. Do not create a second user database or migrate
users by resetting passwords. Before enabling mobile sign-in, add authenticated
API endpoints to the existing server and preserve its current password hashes
and user records. Store Supabase service-role credentials only on the server;
never put them in this Flutter app.

The existing Supabase Storage bucket should remain the video-file store.
