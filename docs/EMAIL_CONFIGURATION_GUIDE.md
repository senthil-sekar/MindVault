# Gmail Integration — Configuration Guide

Step-by-step setup of the Google OAuth client behind MindVault's Gmail sync, plus how the flow
works. For the short version see [ENABLING_EMAIL_FEATURES.md](ENABLING_EMAIL_FEATURES.md).

## Google Cloud setup

### 1. Project and API

1. [console.cloud.google.com](https://console.cloud.google.com/) → **Select a project → New project**
   (e.g. `mindvault`).
2. **APIs & Services → Library** → **Gmail API** → **Enable**.
   Also enable **Google Drive API** if you plan to use the Drive tab.

### 2. OAuth consent screen

1. **APIs & Services → OAuth consent screen** → **External** → Create.
2. App name, support email, developer email. No logo needed while unverified.
3. **Scopes** — add:
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/userinfo.email`
   - `openid`
   These are exactly what `EmailService.gmailScope` requests. Read-only: MindVault never sends,
   deletes, or modifies mail.
4. **Test users** → add every Google account that will connect. While the app is in *Testing*, only
   these accounts can authorize it, and refresh tokens expire after 7 days.

### 3. iOS OAuth client

**Credentials → Create credentials → OAuth client ID → Application type: iOS**

| Field | Value |
|-------|-------|
| Name | MindVault iOS |
| Bundle ID | `com.mindvault.app` |

Google returns a client ID of the form `<NUMBER>-<HASH>.apps.googleusercontent.com`. iOS clients
have **no client secret** — the app uses PKCE instead, which is why nothing secret is checked into
the repo.

## App configuration

### Client ID

`MindVault/Services/EmailService.swift`:

```swift
private let gmailClientId = "<NUMBER>-<HASH>.apps.googleusercontent.com"
private let gmailRedirectURI = "com.mindvault.app:/oauth2redirect"
private let gmailScope = "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/userinfo.email openid"
```

`MindVault/Services/DriveService.swift` holds the equivalent `clientId` for Drive, which uses the
reversed-client-ID redirect `com.googleusercontent.apps.<NUMBER>-<HASH>:/oauth2redirect`.

### URL schemes

`MindVault/Info.plist` must register the scheme of every redirect URI in use:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key><string>com.mindvault.app</string>
    <key>CFBundleURLSchemes</key><array><string>com.mindvault.app</string></array>
  </dict>
  <dict>
    <key>CFBundleURLName</key><string>com.googleusercontent.apps.NUMBER-HASH</string>
    <key>CFBundleURLSchemes</key><array><string>com.googleusercontent.apps.NUMBER-HASH</string></array>
  </dict>
</array>
```

The reversed scheme must match the Drive client ID character for character, or the callback never
returns to the app.

## How the flow works

1. **PKCE pair** — `EmailService.generatePKCEPair()` makes a 128-char verifier and its SHA-256
   challenge.
2. **Authorize** — `ASWebAuthenticationSession` opens Google's consent page with the challenge; the
   user approves; Google calls back on the custom scheme with an auth code.
3. **Token exchange** — code + verifier → `https://oauth2.googleapis.com/token`, returning access,
   refresh, and ID tokens.
4. **Identity** — the account email is read from the ID token (falling back to the userinfo
   endpoint).
5. **Storage** — tokens go to the iOS Keychain via `EmailAccount.saveTokens`; the account record
   goes to SwiftData. `refreshAccessToken` renews expired access tokens automatically.
6. **Sync** — `syncEmails` pulls message IDs, fetches details, parses the MIME payload, strips HTML,
   and stores `EmailMessage` rows; messages deleted in Gmail are removed locally and from the
   vector DB.
7. **Indexing** — each message is posted to `POST /api/upsert/email`, where the backend strips
   signatures and disclaimers, chunks thread-aware with a `Subject`/`Date` header per chunk, and
   upserts embeddings with metadata (`sender`, `subject`, `thread_id`, `labels`, `date`).
8. **Retrieval** — the Email agent filters on `type == "email"` when a chat query looks
   mail-related.

## Reference

| Setting | Where |
|---------|-------|
| Client ID | `EmailService.swift` (`gmailClientId`), `DriveService.swift` (`clientId`) |
| Redirect URI | `EmailService.swift` (`gmailRedirectURI`), `DriveService.swift` (`redirectUri`) |
| URL schemes | `MindVault/Info.plist` → `CFBundleURLTypes` |
| Scopes | `EmailService.gmailScope`, `DriveService.scope` |
| Sync interval | `EmailService.autoSyncInterval` (5 minutes) |
| Messages per sync | `syncEmails(for:limit:)`, default 50 |
| Backend endpoint | `POST /api/upsert/email` |

## Troubleshooting

| Error | Fix |
|-------|-----|
| `redirect_uri_mismatch` | The client is not an iOS client, or its bundle ID isn't `com.mindvault.app` |
| Browser opens, never returns | Redirect scheme missing from `CFBundleURLTypes`, or a typo in the reversed client ID |
| `invalid_client` | Client ID typo, or the client was deleted in the Console |
| `access_denied` / "app not verified" | Account missing from the consent screen's **Test users** |
| `insufficientPermissions` on sync | Gmail API not enabled, or the scope was declined |
| Auth stops working after a week | Testing-mode refresh tokens expire after 7 days — reconnect, or publish the consent screen |
| Emails sync but Chat can't see them | Backend down or wrong Server URL — `curl http://localhost:8000/health` and check `/api/stats` |

## Privacy

Read-only scope; tokens live in the Keychain; message bodies and embeddings live on your device and
your self-hosted backend. Disconnecting an account deletes its Keychain tokens but leaves already
indexed messages in SwiftData and in the vector DB — use **Clear all emails and resync** (or
`docker-compose down -v`) to purge those.
