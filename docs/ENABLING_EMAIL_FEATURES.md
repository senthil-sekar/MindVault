# Enabling Email Features (5 minutes)

The Gmail integration ships in the app but needs one developer-side value: a Google OAuth **iOS
client ID**. Without it, the Connect button in the app is disabled with an explanatory message —
`EmailAccountConnectionView` checks `EmailService.isConfigured()`, which only returns true once
the ID is set. It lives in `Config.local.xcconfig`, not in source.

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

```bash
cp Config.local.xcconfig.example Config.local.xcconfig
```

Set the prefix — the client ID minus the `.apps.googleusercontent.com` suffix:

```
GOOGLE_OAUTH_CLIENT_ID_PREFIX = <NUMBER>-<HASH>
```

That one value feeds the Info.plist `GoogleOAuthClientID` key (read by `Configuration.GoogleOAuth`)
and the reversed-client-ID URL scheme Drive redirects to. `Config.local.xcconfig` is git-ignored, so
the ID never gets committed. Gmail redirects to the bundle-ID scheme `com.mindvault.app` instead;
both schemes are registered in `MindVault/Info.plist`.

## 3. Build and run

⌘R. **Profile → Settings → Email Accounts → Connect Gmail Account** opens an
`ASWebAuthenticationSession`; approve the read-only Gmail scope.

## Using it

- The **Email** tab lists synced messages; pull to refresh or use the sync button.
- Sync fetches up to 50 messages by default, strips HTML, and indexes each one on-device
  (`EmbeddingService` + `LocalVectorStore`, via `VectorDBService`) — no backend involved.
- Auto-sync polls every 5 minutes while the app is running; toggle it in Settings.
- Once indexed, emails are answerable in **Chat** ("what did Alice email me about the invoice?") —
  the app embeds your question on-device and runs a cosine-similarity search across
  `LocalVectorStore`, surfacing whatever's most relevant, email included.
- Messages deleted in Gmail are dropped locally and from `LocalVectorStore` on the next sync.
- Disconnecting an account deletes its Keychain tokens; already indexed messages stay until you
  clear and resync.

## What's stored where

| Data | Location |
|------|----------|
| Access / refresh / ID tokens | iOS Keychain (`EmailAccount.saveTokens`) |
| Account + message records | SwiftData, on device |
| Cleaned email text + embeddings | `LocalVectorStore`, on device |

Nothing goes to a third party for indexing or search — there's no backend. Generation is
on-device too (MLX) unless you've chosen **OpenAI (BYOK)** mode, in which case your question and
retrieved context (which may include email content) go to OpenAI to produce that one answer.

## If it doesn't work

| Symptom | Cause |
|---------|-------|
| Connect button disabled / "not configured" | `gmailClientId` is still empty or malformed |
| Browser sheet shows `redirect_uri_mismatch` | The client ID isn't an **iOS** client, or the bundle ID doesn't match `com.mindvault.app` |
| "Access blocked: app not verified" | Your account isn't in the consent screen's **Test users** |
| Auth succeeds, no messages | Gmail API not enabled on the project |
| Messages sync but Chat can't see them | Run **Settings → Sync All Now** to (re-)index |
