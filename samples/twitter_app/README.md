# twitter_app — InsForge Flutter SDK sample

A Twitter-style app exercising every InsForge module: **auth** (email/password +
PKCE OAuth deep link), **database** (joined feed, like/unlike, pagination),
**storage** (tweet image upload), and **ai** (streaming caption via OpenRouter).

## 1. Configure

Edit `lib/config.dart`:

- `backendUrl` — your InsForge project base URL (no trailing slash, no module
  path). For the Android emulator talking to a local backend use
  `http://10.0.2.2:7130`; for the iOS simulator use `http://localhost:7130`.
- `anonKey` — your project's anon (public) key.
- `openRouterApiKey` — *(optional)* an OpenRouter key to enable "Suggest
  caption". Leave empty to hide the AI button.
- `oauthScheme` — the custom URI scheme for the OAuth redirect
  (default `insforgetwitter`). Must match the platform config below.

## 2. Backend setup (tables, bucket)

Create these tables in your InsForge project:

```sql
create table profiles (
  id uuid primary key references auth_users(id),
  name text,
  bio text,
  avatar_url text
);

create table tweets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  content text not null,
  image_url text,
  created_at timestamptz not null default now()
);

create table likes (
  tweet_id uuid not null references tweets(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (tweet_id, user_id)
);
```

> The feed query joins via the FK constraint name
> `tweets_user_id_fkey`. If your FK is named differently, update the
> `select('*, author:profiles!<your_fk_name>(...)')` string in
> `lib/screens/feed_screen.dart`.

Create a **public** storage bucket named `tweet-images` (Compose uploads images
there and stores the returned public URL on the tweet row).

## 3. OAuth deep-link configuration

The OAuth flow opens the provider URL in the system browser and captures the
redirect back into the app via a custom URI scheme. Register the scheme on each
platform so the OS routes `insforgetwitter://auth-callback` to the app.

### Android — `android/app/src/main/AndroidManifest.xml`

Add an `intent-filter` inside the existing `<activity android:name=".MainActivity">`:

```xml
<intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="insforgetwitter" android:host="auth-callback" />
</intent-filter>
```

### iOS — `ios/Runner/Info.plist`

Add a `CFBundleURLTypes` entry:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>dev.insforge.twitterapp.oauth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>insforgetwitter</string>
        </array>
    </dict>
</array>
```

When configuring the provider in the InsForge dashboard, add
`insforgetwitter://auth-callback` to the allowed redirect URIs.

## 4. Run

```bash
flutter pub get
cd samples/twitter_app
flutter run
```

## What each screen demonstrates

| Screen | Modules | SDK calls |
|---|---|---|
| AuthScreen | auth | `signUp`, `signIn`, `getOAuthUrl` + `handleOAuthCallback` |
| FeedScreen | database | `from('tweets').select(join).order().range().execute()`, like via insert/delete |
| ComposeScreen | storage, database, ai | `storage.from('tweet-images').uploadAutoKey/getPublicUrl`, `database insert`, `ai.chat.completions.createStream` |
| ProfileScreen | auth | `getProfile`, `updateProfile` |
