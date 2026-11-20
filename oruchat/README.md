# OruChat

Free WhatsApp-style Android app: **chat, photos, stories, voice calls, video calls**.
Backend: Supabase (free). APK build: GitHub Actions (free). No server/PC hosting venda.

## 1. Supabase setup (10 minute, oru thavana mathram)

1. https://supabase.com -> your project (URL `lib/config.dart`-il und).
2. Left menu **SQL Editor -> New query**. `supabase/supabase_setup.sql` open cheythu full copy-paste cheythu **RUN**.
   - "Success" kaanikkanam. Storage policy-yil error vannaal: Storage -> New bucket -> name `media` -> **Public** on aakki, SQL veendum run cheyyuka.
3. **Authentication -> Sign In / Providers -> Email**: **"Confirm email" OFF** aakkuka (illenkil signup kazhinju login cheyyaan email confirm cheyyanam).
4. **Project Settings -> API Keys**: Project URL, Publishable key `lib/config.dart`-il ullathumayi same aano ennu nokkuka. Alla enkil config.dart-il maattuka.

## 2. APK undaakkuka (GitHub, free, PC-il onnum install venda)

1. https://github.com -> free account -> **New repository** -> name `oruchat` -> **Public** -> Create.
2. **uploading an existing file** click cheythu, ee zip extract cheytha folder-ile **ellaa files & folders-um** (hidden `.github` folder ulppede) drag & drop cheythu **Commit changes**.
   - `.github` folder upload aayilla enkil: **Add file -> Create new file**, name-il `.github/workflows/build_apk.yml` ennu type cheythu, `build_apk.yml` (zip-ile root file) content paste cheythu commit cheyyuka.
3. **Actions** tab -> **Build OruChat APK** -> (automatic start aakum; allenkil **Run workflow**). 10-15 minute edukkum.
4. Green tick vannaal aa run open cheythu thaazhe **Artifacts -> OruChat-APK** download cheyyuka. Zip extract cheythal `app-release.apk`.
5. APK phone-ilekku ayakkuka (WhatsApp/USB), open cheythu **Install** (Install unknown apps allow cheyyanam).

Red X vannaal: run open cheythu failed step-inte error text copy cheythu Claude-ine ayakkuka, fix cheythu tharum.

## 3. Test

Randu phone-il randu account undaakkuka (email + password + username). Chats -> chat button -> username search -> chat, photo, voice/video call, Stories tab-il story idukka.

## Limitations (sathyam ariyanam)

- **App close aayirikkumbol notification / call ring varilla.** (Push notification-inu Firebase setup venam; athu free aanu, pinne cheyyaam.)
- Calls: free public TURN server aanu use cheyyunnath (`lib/config.dart`). Chila mobile networks-il connect aavilla. Better aakkaan metered.ca / Cloudflare-il free TURN account undaakki details config.dart-il idaam.
- Phone-number login illa (SMS OTP-ku paisa venam). Email + username aanu.
- Group chat, end-to-end encryption, message delete illa. Photos "public link" aayi store cheyyunnu (guess cheyyaan paattaatha pathname).
- Supabase free plan: kure divasam upayogikkaathirunnaal project pause aakum (dashboard-il Restore cheyyaam). 1 GB storage.
- Ee code compile cheythu test cheythittilla (build environment ente kayyil illa) - first build-il chila errors vannekkaam.

## Feature completion upgrade (added in this ZIP)

After the original `supabase/supabase_setup.sql` has been run, run the new
`supabase/feature_completion.sql` in Supabase Dashboard → SQL Editor. This adds
the database tables, indexes, row-level security policies and RPC used by the
features below. Do not skip the migration.

### Added in this upgrade

- **Documents:** attach files from the Android system picker (PDF, Word, Excel
  and other file types) to one-to-one and group chats. Files are uploaded to the
  existing `media` Supabase Storage bucket.
- **Voice messages:** record AAC voice notes with microphone permission, upload
  them to Storage and play them inside the conversation.
- **Video sharing:** choose a video from the gallery, upload it and share its
  link in a chat. The current chat bubble opens the video link externally.
- **24 image filters:** 24 actual pixel-processing presets (not just icons) are
  available before a photo story is uploaded and before an image is sent in a
  one-to-one chat. The filtered JPEG bytes, rather than the original image, are uploaded.
- **Chat lock:** each one-to-one chat can be protected with a 4–8 digit PIN.
  Android biometric/device authentication is attempted first; PIN is the
  fallback. The PIN is stored using platform secure storage on that device.
- **Group messaging:** create groups by entering a group name and comma-separated
  usernames, view groups, send text and document messages, and view/add members.
  Supabase RLS restricts group content to members and member management to the
  group creator/admin.
- **View-once:** mark the next outgoing message as view-once. The recipient
  consumes it through the `consume_view_once_message` RPC; the database deletes
  the row atomically after returning it, so it cannot be fetched a second time.
- **Disappearing messages:** choose Off, 1 minute, 1 hour, 24 hours or 1 month.
  The per-chat preference is saved per user, and each subsequent message gets
  its own expiry timestamp. Expired messages are hidden by RLS. The migration
  also installs periodic cleanup when `pg_cron` is enabled; otherwise cleanup
  runs opportunistically when new messages are inserted.

### Android build notes

The build workflow runs `tool/patch_android.dart`, which adds biometric
permissions and configures `MainActivity` as `FlutterFragmentActivity` for
`local_auth`. Microphone permission is required for voice notes. The app will
request it through the recorder when the user first records.

### Important limitations / deployment checks

- This upgrade is an implementation pass, not a verified production release.
  Run the Supabase migration, then build and test on two physical Android
  devices before distributing the APK.
- Supabase Storage currently uses the project's existing `media` bucket and
  its existing public-read policy. Uploaded attachments therefore use public
  URLs; do not use this storage configuration for confidential documents.
- PIN/biometric chat lock is device-local. Reinstalling the app or moving to a
  different phone does not transfer the lock configuration.
- A view-once message is removed from the server when the recipient opens it;
  this cannot prevent screenshots, screen recording or a recipient photographing
  the screen with another device.
- Story filters are applied to uploaded photos. Video filters, group voice/video
  calls, end-to-end encryption, and remote push notifications are not included
  in this specific feature-completion pass.
- Disappearing-message preference is saved per sender/device account. It applies
  to messages sent after the setting is selected, not retroactively to older
  messages.
