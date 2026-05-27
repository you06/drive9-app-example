# Drive9 App Examples

Minimal iOS and Android examples for the Drive9 mobile SDKs.

The examples connect to an existing Drive9 space. They only ask for:

- Drive9 base URL, such as `https://example.com`
- Existing Drive9 API key or scoped token

They do not create spaces, issue tokens, or call owner/admin APIs.

## Examples

- `ios/Drive9Example` - SwiftUI app using the Swift facade.
- `android` - Kotlin Android app using the Kotlin facade.

Both demos support:

- Recording audio and uploading it to `/mobile-demo/audio`.
- Recording an audio query and searching `/mobile-demo/audio` with Drive9's
  file-based semantic search helper from PR #469.
- Viewing read-only search results with semantic summaries and playable audio.

Drive9 extracts semantic text asynchronously. The search action uploads the
query recording to a temporary path, waits for semantic text, searches
`/mobile-demo/audio`, and then shows the result list.

## SDK Source

The Drive9 mobile SDKs currently live in the Drive9 repository under `clients/`.
Clone it locally before opening the examples:

```bash
./scripts/bootstrap-drive9-sdk.sh
```

This creates `vendor/drive9` and checks out the Drive9 SDK branch that contains
the file-based semantic search helper (`feat/semantic-search-by-file-sdk` by
default). After PR #469 is merged, set `DRIVE9_REF=main` if you want to consume
the merged branch. You can also set `DRIVE9_REPO=/path/to/drive9` when following
the platform-specific READMEs.

The current Swift and Kotlin SDKs use native HTTP implementations. These demos
do not require Rust, UniFFI, generated bindings, shared libraries, `jniLibs`, or
`DYLD_LIBRARY_PATH`.
