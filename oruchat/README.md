# OruChat v2  —  by Oru Design Creative Studio (www.orudesign.in)

Flutter Android messaging app with a WhatsApp + Snapchat-inspired feature set. Backend: your existing Supabase project. APK build: GitHub Actions.

## v2-il ullathu
Chat, photos, video, voice message, audio/document sharing, location sharing, stickers,
one-time messages, disappearing messages (1 min / 1 hour / 24 hour / 1 month), clear chat,
message search (chat-ilum ellaa chats-ilum), group chat, 27 photo filters (stories + chat photos),
friend requests (voice/video call friends thammil mathram), block / unblock, username edit,
privacy settings (photo, about, last seen, online, status, who can message), chat lock (PIN),
Terms & Conditions, About (Oru Design Creative Studio), Support (UPI + QR).

## UPDATE cheyyunna vidham (v1 already GitHub-il undenkil)

### 1) Supabase  (MUKHYAM - aadyam ith cheyyanam)
1. supabase.com -> project -> **SQL Editor -> New query**.
2. `oruchat/supabase/supabase_setup.sql` full copy -> paste -> **RUN**. "Success" varanam.
   **Ithu existing Supabase project-il veendum RUN cheyyanam.** App update mathram cheythaal RPC/column errors maarilla.
3. SQL run kazhinju Supabase-il 1-2 minutes wait cheyyuka; app close cheythu reopen cheyyuka.
4. `public.messages` table-il `once` column undennum, Database -> Functions-il `search_profile_ids`, `change_username`, `get_profiles` undennum verify cheyyuka.
5. Authentication -> Email -> "Confirm email" OFF aayirikkanam (munpu cheythittundenkil veendum venda).

### 2) GitHub
1. Ee zip extract cheyyuka.
2. Ningalude repo-yil **Add file -> Upload files** -> extracted folder-ile `oruchat` folder-um `.github` folder-um drag & drop -> **Commit changes**. (Same file names overwrite aakum.)
3. Repo-yil `.github/workflows/dart.yml` undenkil athu **delete** cheyyuka (ath default Dart template aanu, red X varum). `build_apk.yml` mathram mathi.
4. **Actions** tab -> "Build OruChat Android APK" thaanae start aakum -> 10-15 min -> Artifacts -> **OruChat-Android-APK** download -> `app-release.apk` phone-il install.

IMPORTANT: Ellaa phone-ilum puthiya APK install cheyyanam. Pazhaya (v1) app puthiya database-umayi work cheyyilla.

## Current bug-fix notes
- Find people uses `search_profile_ids(q)`; the SQL setup now creates it.
- Username editing uses `change_username(new_username)`; the SQL setup now creates it.
- Message search filters `messages.once`; the SQL setup adds this column.
- Profile loading uses `get_profiles(ids)`; the SQL setup creates it and backfills missing profile rows for existing Auth users.
- These are Supabase database changes. **The SQL must be run in the same Supabase project used by the app.** A new APK alone cannot fix missing database functions or columns.

## OruChat repair package notes

- Signup now validates the email format and gives the correct Supabase setting guidance when `signUp` returns no session. For password-only login (no email OTP/confirmation), set **Authentication -> Providers -> Email -> Confirm email = OFF** in the existing Supabase project. Do not disable password security or expose a service-role key in the app.
- The `open_once(mid)` database function is updated to claim a one-time message atomically, preventing concurrent opens from returning the same payload twice. Re-run the complete SQL file in the same existing project.
- The app's Supabase URL and publishable/anon key are currently configured in `lib/config.dart`; these are client-side values. Never place a `service_role` key in Flutter or GitHub client build arguments.

## Required validation before public release

This package is a repaired source baseline, **not a verified production release**. The existing Supabase project is private and cannot be accessed or migrated from this workspace, and this environment does not have the Flutter SDK installed to run `flutter analyze` or build an APK. Build it with the included GitHub Actions workflow, then test with two separate accounts/devices. In particular, confirm signup/login, friend requests, text/media/voice messages, stories, groups, block/privacy rules, and voice/video calls.

Known release blockers/limitations in this codebase: media is stored in a public Supabase Storage bucket (do not upload sensitive/private media); message contents are not end-to-end encrypted; background incoming-call delivery is not implemented; public/free TURN relay availability is not guaranteed; screenshot prevention/notification cannot be guaranteed on Android; and the SQL scheduled cleanup depends on `pg_cron` being available. Do not advertise these as secure or fully reliable until independently implemented and tested.

## Ariyendath
- Database-side fixes are included in the SQL, but I cannot connect to your private Supabase project from here to run it or verify live data. After running the SQL, test the items above on two accounts.
- Compile cheythu test cheythittilla. First build-il error vannaal log text ayachu tharoo.
- Notification / call ring: app close aayirikkumbol varilla (Firebase venam).
- Calls: friends thammil mathram. Free TURN server aanu -> chila networks-il connect aavilla.
- Messages end-to-end encrypted alla. Photos/videos/files "hard-to-guess public link" aayi store cheyyunnu.
- One-time message: receiver thurannaal server-il ninnu content delete aakum; screenshot thadayilla.
- Disappearing messages: setting on aakkiya sheshamulla puthiya messages-ine mathram bhaadhikkum.
- Chat lock PIN ee phone-il mathram (PIN marannaal chat thurakkaan app reinstall venam).
- Clear chat: ningalude view-il mathram.
- File size max 48 MB (Supabase free limit 50 MB).
- Groups: friends-ine mathram add cheyyam; group call illa.
- Terms & Conditions oru draft aanu - launch-inu munpu oru lawyer-ne kaanikkuka.
