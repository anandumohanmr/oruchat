# OruChat v3  —  by Oru Design Creative Studio (www.orudesign.in)

## v3-il maattiyath (bug fixes)
- Signup/login: email + password mathram, OTP/confirm-email venda. SQL-il auto-confirm trigger add cheythu; app signup kazhinju udane login cheyyum. Clear error messages.
- Profile trigger safe aakki (username clash-il signup fail aakilla).
- Calls: ICE candidates offer-inu munpe ethunna race fix (calls connect aakathirunnathinte main kaaranam), reconnect status, extra permissions.
- Messages: receiver-inu read_at mathram maattaan pattu (security).
- Find people/profile load error ippo screen-il kaanikkum.

## ORU THAVANA CHEYYENDATHU (Supabase dashboard)
1. SQL Editor -> `oruchat/supabase/supabase_setup.sql` full paste -> RUN (ippozhathe project-il thanne).
2. Authentication -> Providers -> Email -> **Confirm email = OFF** (Save). Ith OFF aakkiyillenkil Supabase-inte free email limit (2/hour) kaaranam signup error varum.
3. Pazhaya app uninstall cheythu puthiya APK install cheyyuka.

Free WhatsApp-style Android app. Backend: Supabase (free). APK build: GitHub Actions (free).

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
