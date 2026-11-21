import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'utils.dart';

const String kTermsText = '''
Last updated: November 2026

Welcome to OruChat, an app developed by Oru Design Creative Studio (www.orudesign.in). By creating an account or using OruChat you agree to these Terms and Conditions. If you do not agree, please do not use the app.

1. Your account
• You must provide a correct email address and keep your password secret.
• You are responsible for everything that happens through your account.
• You must be old enough to use online messaging services in your country.

2. Acceptable use
You agree NOT to use OruChat to:
• send spam, scams, threats, hate speech, harassment or abusive content;
• share illegal content, or content that exploits or harms children;
• share content that you do not have the right to share;
• impersonate other people, or try to hack, overload or misuse the service;
• record or share other people's private information without permission.
We may suspend or delete accounts that break these rules.

3. Your content
You own the messages, photos, videos, voice messages, documents, locations and stories you share. You give OruChat permission to store and deliver them so that the app can work. Please share only what you are comfortable sharing.

4. Privacy
• Your profile name, username and email, your messages, media files, friend connections, stories and call information are stored on our cloud service provider (Supabase).
• You can control who sees your profile picture, about text, last seen, online status and stories, and who can message you, from Settings > Privacy.
• Chat lock and its PIN are stored only on your own phone. If you forget the PIN you may have to reinstall the app.
• Disappearing messages are deleted from the server after the time you choose. One-time messages are removed from the server after the receiver opens them. Anyone can still take a screenshot or photo of a message, so only share with people you trust.
• Photos, videos and files are stored as web links that are hard to guess, but anyone who has the exact link can open it.
• Messages are not end-to-end encrypted in this version.
• We do not sell your personal information.

5. Friends, blocking and calls
Voice and video calls are available only between people who have accepted each other's friend request. You can block anyone at any time. Blocked people cannot message or call you.

6. Location sharing
When you choose to share your location, your current position is sent only in that chat. Never share your location with people you do not trust.

7. No guarantee
OruChat is provided "as is", free of cost. We try to keep it working, but we do not promise that it will be always available, error free, or that messages, calls or files will never be lost. Do not use OruChat for emergencies.

8. Limitation of liability
To the maximum extent allowed by law, Oru Design Creative Studio is not responsible for any loss or damage caused by using the app, by other users' content or behaviour, or by service interruptions.

9. Support
Support of the developer through the "Support the app" option is completely voluntary. It does not give you any special rights, and payments are not refundable unless required by law.

10. Changes and ending
We may update these Terms or the app. If you keep using OruChat after a change, you accept the new Terms. You can delete your account by contacting us.

11. Contact
Oru Design Creative Studio - www.orudesign.in
''';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Text(kTermsText, style: TextStyle(fontSize: 15, height: 1.45)),
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About OruChat')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(child: Image.asset('assets/brand/wordmark.png', height: 80)),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Version ${AppInfo.version}',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Developed by',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 4),
          const Text(
            AppInfo.studioName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: purple,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => openUrl(context, AppInfo.studioSite),
            icon: const Icon(Icons.language_rounded),
            label: const Text('www.orudesign.in'),
          ),
          const SizedBox(height: 28),
          ListTile(
            leading: const Icon(Icons.description_outlined, color: purple),
            title: const Text('Terms & Conditions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const TermsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.favorite_rounded, color: purple),
            title: const Text('Support the app'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SupportPage())),
          ),
        ],
      ),
    );
  }
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  Future<void> _payWithUpi(BuildContext context) async {
    final uri = Uri.parse(
      'upi://pay?pa=${AppInfo.upiId}&pn=${Uri.encodeComponent(AppInfo.studioName)}&cu=INR&tn=${Uri.encodeComponent('OruChat support')}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        snack(
          context,
          'No UPI app found. Scan the QR code or copy the UPI ID.',
        );
      }
    } catch (_) {
      if (context.mounted)
        snack(
          context,
          'No UPI app found. Scan the QR code or copy the UPI ID.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support the app')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'OruChat is free and has no ads. If you like it, you can support its development with a small voluntary contribution. Thank you! 💜',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/brand/upi_qr.jpg'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.account_balance_wallet_outlined,
                color: purple,
              ),
              title: const Text('UPI ID'),
              subtitle: const SelectableText(AppInfo.upiId),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: AppInfo.upiId),
                  );
                  if (context.mounted) snack(context, 'UPI ID copied');
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _payWithUpi(context),
            style: FilledButton.styleFrom(
              backgroundColor: purple,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.payment_rounded),
            label: const Text('Pay with a UPI app'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Support is completely voluntary and is not required to use any feature.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
