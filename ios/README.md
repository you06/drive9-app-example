# iOS Drive9 Example

SwiftUI demo for the Drive9 Swift SDK.

## Setup

1. Clone the latest native SDK source:

```bash
../scripts/bootstrap-drive9-sdk.sh
```

2. Open `Drive9Example/Drive9Example.xcodeproj`.

The Xcode project already references the local Swift package at:

```text
../../vendor/drive9/clients/drive9-swift
```

If you use a different checkout, update the local package path in Xcode or set
up `vendor/drive9` with the bootstrap script.

The Swift SDK is a native HTTP implementation. No Rust build, UniFFI generation,
C bridge, shared library, linker flag, or `DYLD_LIBRARY_PATH` is needed.

The SDK package and this example target are configured for iOS 21 or newer.

## Usage

Enter the Drive9 base URL and an existing Drive9 API key/token, pick a local
file, upload it to `/mobile-demo/`, then search with a natural-language query.
The search button uses `grep`, which Drive9 serves as semantic / full-text /
keyword hybrid search. New uploads may need a short indexing delay before they
appear in semantic results.
