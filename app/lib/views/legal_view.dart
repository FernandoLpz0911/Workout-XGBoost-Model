import 'package:flutter/material.dart';

class LegalView extends StatelessWidget {
  final String title;
  final String body;
  const LegalView({super.key, required this.title, required this.body});

  static void showPrivacy(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LegalView(
              title: 'Privacy Policy', body: _kPrivacyPolicy)));

  static void showTerms(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LegalView(
              title: 'Terms of Service', body: _kTerms)));

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
          style: const TextStyle(
              color: Colors.grey, fontSize: 13, height: 1.7),
        ),
      ),
    );
  }
}

// ── Policy text ───────────────────────────────────────────────────────────────

const _kPrivacyPolicy = '''
Last updated: June 2026

RepIQ ("we", "our", or "the app") is built for personal use and takes your privacy seriously. This policy describes what data we collect and how it is used.

INFORMATION WE COLLECT

• Account data: when you sign in with Google we receive your name, email address, and profile photo from Google Sign-In.
• Workout data: exercises, sets, weights, reps, rest times, and any notes you type during a session.
• Usage data: anonymous analytics events (e.g. session started, set logged) collected via Firebase Analytics to understand how the app is used.
• Crash reports: stack traces and device info collected via Firebase Crashlytics when the app crashes, to help us fix bugs.

HOW WE USE YOUR DATA

• Workout data is stored on your device (SQLite) and optionally backed up to Firebase Firestore under your account so you don't lose it if you change phones.
• If you are a Premium subscriber and choose to retrain the cloud model, your workout CSV is uploaded to our Google Cloud Run backend, used to train a personal XGBoost model, and then discarded. The model is stored in Google Cloud Storage under your user ID and is never shared.
• We do not sell your data to third parties.
• Analytics data is aggregated and used only to improve the app.

THIRD-PARTY SERVICES

The app uses the following Google/Firebase services, each governed by Google's Privacy Policy (policies.google.com/privacy):
• Firebase Authentication
• Firebase Firestore
• Firebase Analytics
• Firebase Crashlytics
• Google Cloud Run & Cloud Storage (premium features)

DATA RETENTION AND DELETION

You can delete all locally stored data at any time from Settings → Clear All Local Data. To request deletion of your Firestore data and account, contact us at the email below. Cloud model files are deleted automatically if your account is removed.

CHILDREN

RepIQ is not directed at children under 13. We do not knowingly collect data from children.

CONTACT

Questions? Email: fernandolpz0911@gmail.com
''';

const _kTerms = '''
Last updated: June 2026

Please read these Terms of Service carefully before using RepIQ.

1. ACCEPTANCE

By using RepIQ you agree to these terms. If you do not agree, do not use the app.

2. DESCRIPTION OF SERVICE

RepIQ is a personal workout logging and AI recommendation app. It provides exercise suggestions based on your logged history using on-device algorithms and, for Premium subscribers, a cloud-trained XGBoost model.

3. NOT MEDICAL ADVICE

RepIQ is a fitness tool, not a medical device. Recommendations are algorithmic, not from certified trainers or physicians. Always consult a qualified professional before starting a new exercise program. We are not liable for any injuries that occur while following the app's recommendations.

4. SUBSCRIPTIONS

Premium features are available via a monthly or annual subscription purchased through Google Play. Subscriptions auto-renew unless cancelled at least 24 hours before the current period ends. Manage or cancel your subscription in Google Play → Account → Subscriptions. We do not offer refunds beyond what Google Play's policies require.

5. USER CONTENT

You are responsible for the accuracy of data you log. Workout data is yours — we do not claim any ownership over it.

6. PROHIBITED USE

You may not reverse-engineer, decompile, or attempt to extract the source code of RepIQ. You may not use the app for any unlawful purpose.

7. DISCLAIMER OF WARRANTIES

RepIQ is provided "as is" without warranties of any kind. We do not guarantee that the app will be error-free or uninterrupted.

8. LIMITATION OF LIABILITY

To the fullest extent permitted by law, we are not liable for any indirect, incidental, or consequential damages arising from your use of RepIQ.

9. CHANGES

We may update these terms at any time. Continued use of the app after changes constitutes acceptance.

10. CONTACT

Questions? Email: fernandolpz0911@gmail.com
''';
