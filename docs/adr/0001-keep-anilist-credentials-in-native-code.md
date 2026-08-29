# Keep AniList credentials in native code

AniSync will support one connected AniList account at a time, store its broad, long-lived OAuth token in the macOS Keychain, and perform AniList requests through native extension code. Website and extension JavaScript will never receive the credential; this accepts a native messaging boundary instead of the simpler background-JavaScript client because exposure would grant a compromised script almost full access to the user's AniList account.
