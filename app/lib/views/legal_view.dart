import 'package:flutter/material.dart';

class LegalView extends StatelessWidget {
  final String title;
  final String body;
  const LegalView({super.key, required this.title, required this.body});

  static void showPrivacy(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LegalView(title: 'Privacy Policy', body: _kPrivacyPolicy),
    ),
  );

  static void showTerms(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LegalView(title: 'Terms of Service', body: _kTerms),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1117),
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        leading: const BackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Text(
          body,
          style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.7),
        ),
      ),
    );
  }
}

// ── Policy text ───────────────────────────────────────────────────────────────

const _kPrivacyPolicy = '''
Last updated: June 2026

RepIQ is a fully offline, open-source app. It does not collect, transmit, or share any data.

INFORMATION WE COLLECT

None. RepIQ has no internet connection, no accounts, and no analytics. All data stays on your device.

YOUR WORKOUT DATA

• Everything you log — exercises, sets, weights, reps, notes — is stored only on your device using SQLite.
• No data is ever sent to a server or third party.
• You can delete all stored data at any time from Settings → Clear All Local Data.

OPEN SOURCE

RepIQ is open-source software. The full source code is publicly available for review.

CONTACT

Questions? Email: fernandolpz0911@gmail.com
''';

const _kTerms = '''
Last updated: June 2026

1. ACCEPTANCE

By using RepIQ you agree to these terms.

2. DESCRIPTION OF SERVICE

RepIQ is a free, open-source, fully offline workout logging and AI recommendation app. It provides exercise suggestions based on your logged history using on-device algorithms. No internet connection is required.

3. NOT MEDICAL ADVICE

RepIQ is a fitness tool, not a medical device. Recommendations are algorithmic, not from certified trainers or physicians. Always consult a qualified professional before starting a new exercise program. We are not liable for any injuries that occur while following the app's recommendations.

4. USER CONTENT

All workout data is stored only on your device. You own it completely. Clearing the app data or uninstalling will delete it permanently.

5. OPEN SOURCE

RepIQ is open-source software provided under its license terms. You are free to view, fork, and contribute to the source code.

6. DISCLAIMER OF WARRANTIES

RepIQ is provided "as is" without warranties of any kind. We do not guarantee that the app will be error-free or uninterrupted.

7. LIMITATION OF LIABILITY

To the fullest extent permitted by law, we are not liable for any indirect, incidental, or consequential damages arising from your use of RepIQ.

8. CONTACT

Questions? Email: fernandolpz0911@gmail.com
''';
