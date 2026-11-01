# VidShare Mobile

Flutter client for the existing VidShare Flask server. The mobile app shares the same users, videos, likes, subscriptions and comments tables as the PC website.

## Connected features

- Login with an existing PC VidShare account
- Signup using the same server user table
- Home recommendation feed and video search
- Subscriptions feed
- Video playback, view count, likes and comments
- Follow/unfollow channels
- Upload MP4, WEBM, OGG and MOV videos
- Library lists for your uploads and liked videos
- API bearer tokens are stored using platform secure storage

## Server API

The Flask backend exposes these mobile endpoints:

- POST /api/mobile/auth/login
- POST /api/mobile/auth/register
- GET /api/mobile/auth/me
- POST /api/mobile/auth/logout
- GET /api/mobile/videos?feed=home|subscriptions|mine|liked
- GET /api/mobile/videos/<id>
- POST /api/mobile/videos (multipart video upload)
- POST /api/mobile/videos/<id>/like
- POST /api/mobile/videos/<id>/comments
- POST /api/mobile/channels/<id>/subscribe

Tokens expire after 30 days. Logging out revokes the current token. The PC website's existing cookie-session login continues to work independently.

## Run locally

Install Flutter stable and Android Studio. The source is in this folder:

1. Open a terminal in the mobile folder.
2. Run flutter pub get.
3. Run flutter run.
4. On the first login screen, enter the actual HTTPS URL of the deployed VidShare Render service, then use your existing PC nickname and password.

## Build a release APK

Run this from the mobile folder:

    flutter build apk --release --dart-define=VIDSHARE_API_URL=https://YOUR-VIDSHARE-HOST

The server URL can also be entered and saved in the app login screen. Do not commit credentials, API tokens, or payment provider secrets to this repository.

## Platform folders

This repository currently stores the Flutter lib/ source and pubspec.yaml. If the generated android/ or ios/ folders are not present in your checkout, generate the platform projects once from this directory:

    flutter create --platforms=android,ios --project-name=vidshare_mobile .
    flutter pub get

For iOS builds, use macOS with Xcode.

## Storage note

The current PC Flask app in this repository saves uploaded video files under VIDSHARE_UPLOAD_DIR (by default inside the configured persistent data directory) and stores account/video metadata in SQLite. The mobile client uses those same PC server routes and storage locations. A Supabase Storage bucket is not configured by this repository's current Flask code; do not assume files are being uploaded to that bucket yet.
