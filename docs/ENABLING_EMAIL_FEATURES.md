# Enabling Email Features (5 minutes)

The Gmail integration ships in the app but needs one developer-side value: a Google OAuth **iOS
client ID**. Without it every connect attempt fails, because `EmailService.isConfigured()` only
returns true when `gmailClientId` looks like a real client ID.

If you just want to *use* an already-configured build, skip to [Using it](#using-it).

## 1. Create the OAuth client (one time)

1. [Google Cloud Console](https://console.cloud.google.com/) → create or pick a project.
2. **APIs & Services → Library** → enable **Gmail API**.
3. **OAuth consent screen** → External → add your Google account under **Test users**
   (an unverified app can only be used by listed test users).
4. **Credentials → Create credentials → OAuth client ID → iOS**, bundle ID `com.mindvault.app`.
5. Copy the client ID: `<NUMBER>-<HASH>.apps.googleusercontent.com`.

Detailed walkthrough with the scope list: [EMAIL_CONFIGURATION_GUIDE.md](EMAIL_CONFIGURATION_GUIDE.md).

## 2. Put it in the app

`MindVault/Services/EmailService.swift`:

```swift
private let gmailClientId = "<NUMBER>-<HASH>.apps.googleusercontent.com"
private let gmailRedirectURI = "com.mindvault.app:/oauth2redirect"
```

The redirect URI's scheme (`com.mindvault.app`) is already registered under `CFBundleURLTypes` in
`MindVault/Info.plist`. Google Drive uses a separate reversed-client-ID scheme, also in that file.

## 3. Build and run

⌘R. **Profile → Settings → Email Accounts → Connect Gmail Account** opens an
`ASWebAuthenticationSession`; approve the read-only Gmail scope.

## Using it

- The **Email** tab lists synced messages; pull to refresh or use the sync button.
- Sync fetches up to 50 messages by default, strips HTML, and posts each one to
  `POST /api/upsert/email` so the backend can chunk and index it.
- Auto-sync polls every 5 minutes while the app is running; toggle it in Settings.
- Once indexed, emails are answerable in **Chat** ("what did Alice email me about the invoice?") —
  the backend's Email agent handles those queries.
- Messages deleted in Gmail are dropped locally and from the vector DB on the next sync.
- Disconnecting an account deletes its Keychain tokens; already indexed messages stay until you
  clear and resync.

## What's stored where

| Data | Location |
|------|----------|
| Access / refresh / ID tokens | iOS Keychain (`EmailAccount.saveTokens`) |
| Account + message records | SwiftData, on device |
| Cleaned email text + embeddings | Your Qdrant instance, via the backend |

Nothing goes to a third party: the LLM is local Ollama and the vector DB is yours.

## If it doesn't work

| Symptom | Cause |
|---------|-------|
| Connect button disabled / "not configured" | `gmailClientId` is still empty or malformed |
| Browser sheet shows `redirect_uri_mismatch` | The client ID isn't an **iOS** client, or the bundle ID doesn't match `com.mindvault.app` |
| "Access blocked: app not verified" | Your account isn't in the consent screen's **Test users** |
| Auth succeeds, no messages | Gmail API not enabled on the project |
| Messages sync but Chat can't see them | Backend unreachable — check `curl http://localhost:8000/health` and the Server URL in Settings |
