# iOS Drive9 Example

SwiftUI demo for the Drive9 Swift SDK.

## Setup

1. Clone the SDK source:

```bash
../scripts/bootstrap-drive9-sdk.sh
```

2. Generate Swift bindings and build the native library:

```bash
(cd ../vendor/drive9/clients/drive9-mobile-core && ./scripts/regenerate-bindings.sh)
```

3. Open `Drive9Example/Drive9Example.xcodeproj`.
4. In Xcode, add the local Swift package at:

```text
../vendor/drive9/clients/drive9-swift
```

5. Link `Drive9Mobile` to the app target.
6. Ensure the built native library is available to the app. For simulator
   development, point the run environment at:

```text
DYLD_LIBRARY_PATH=$(SRCROOT)/../../vendor/drive9/clients/drive9-mobile-core/target/release
```

Production iOS packaging should use a proper XCFramework / binary target. This
example intentionally stays as a local SDK integration demo.

## Usage

Enter the Drive9 base URL and an existing Drive9 API key/token, pick a local
file, upload it to `/mobile-demo/`, then search with a natural-language query.
The search button uses `grep`, which Drive9 serves as semantic / full-text /
keyword hybrid search. New uploads may need a short indexing delay before they
appear in semantic results.
