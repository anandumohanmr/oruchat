# OruChat v2  —  by Oru Design Creative Studio (www.orudesign.in)

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
   (V1 munpu run cheythittundenkilum safe aanu; puthiya tables/functions add aakum.)
3. Authentication -> Email -> "Confirm email" OFF aayirikkanam (munpu cheythittundenkil veendum venda).

### 2) GitHub
1. Ee zip extract cheyyuka.
2. Ningalude repo-yil **Add file -> Upload files** -> extracted folder-ile `oruchat` folder-um `.github` folder-um drag & drop -> **Commit changes**. (Same file names overwrite aakum.)
3. Repo-yil `.github/workflows/dart.yml` undenkil athu **delete** cheyyuka (ath default Dart template aanu, red X varum). `build_apk.yml` mathram mathi.
4. **Actions** tab -> "Build OruChat Android APK" thaanae start aakum -> 10-15 min -> Artifacts -> **OruChat-Android-APK** download -> `app-release.apk` phone-il install.

IMPORTANT: Ellaa phone-ilum puthiya APK install cheyyanam. Pazhaya (v1) app puthiya database-umayi work cheyyilla.

## Ariyendath
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
