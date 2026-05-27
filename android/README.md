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
- Record an audio query and search `/mobile-demo/audio` with the Drive9
  `searchByFile` helper from PR #469.

Search results open in a read-only list. Each result shows the semantic summary
Drive9 extracted for that recording and includes a play button that downloads
and plays the matching audio file.

Drive9 extracts semantic text asynchronously, so search may wait up to the SDK
timeout for the query recording to become searchable.
