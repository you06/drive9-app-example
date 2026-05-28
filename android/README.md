# Android Drive9 Example

Kotlin Android demo for the Drive9 Kotlin SDK.

## Setup

1. Clone the latest native SDK source:

```bash
../scripts/bootstrap-drive9-sdk.sh
```

2. Open `android/` in Android Studio.

The Gradle settings include the Kotlin SDK from:

```text
../vendor/drive9/clients/drive9-kotlin/lib
```

You can override this with `DRIVE9_REPO=/path/to/drive9`.

The Kotlin SDK is a native HTTP implementation. No Rust build, UniFFI
generation, JNA dependency, native shared library, or `jniLibs` packaging is
needed.

## Usage

Enter the Drive9 base URL and an existing Drive9 API key/token. The default
server is `https://api.drive9.ai`.

The main screen has two workflows:

- Record audio and upload it to `/mobile-demo/audio`.
- Pick a language (中文 / English / 日本語), speak a search query, and search
  `/mobile-demo/audio`. Transcription comes from the system speech
  recognizer launched via `RecognizerIntent`. The transcribed query is sent
  to the existing Drive9 `grep` endpoint.

The transcribed query is shown in an editable text field so you can fix any
recognition mistakes before tapping Search Recordings.

Search results open in a read-only list with name, the Drive9-extracted
semantic summary, size, match score, and a play button that downloads and
plays the matching audio file.

Drive9 indexes uploaded recordings asynchronously on the backend, so a freshly
uploaded clip becomes searchable - and gains its semantic summary - after the
server finishes processing it.
