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
