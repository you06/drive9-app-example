# Drive9 App Examples

Minimal iOS and Android examples for the Drive9 mobile SDKs.

The examples connect to an existing Drive9 space. They only ask for:

- Drive9 base URL, such as `https://example.com`
- Existing Drive9 API key or scoped token
- Remote upload path and search prefix

They do not create spaces, issue tokens, or call owner/admin APIs.

## Examples

- `ios/Drive9Example` - SwiftUI app using the Swift facade.
- `android` - Kotlin Android app using the Kotlin facade.

Both demos support:

- Uploading a local file to Drive9.
- Semantic search with `grep`, which Drive9 implements as hybrid semantic / full-text / keyword search.

New uploads may take a short time to appear in semantic results while Drive9
indexes the file.

## SDK Source

The Drive9 mobile SDKs currently live in the Drive9 repository under `clients/`.
Clone it locally before opening the examples:

```bash
./scripts/bootstrap-drive9-sdk.sh
```

This creates `vendor/drive9`. You can also set `DRIVE9_REPO=/path/to/drive9`
when following the platform-specific READMEs.
