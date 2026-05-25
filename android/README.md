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

Enter the Drive9 base URL and an existing Drive9 API key/token. Choose a local
document through Android's file picker, upload it to `/mobile-demo/`, then run a
natural-language search. The search button uses `grep`, which Drive9 serves as
semantic / full-text / keyword hybrid search. New uploads may need a short
indexing delay before they appear in semantic results.
