import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin wrapper around FirebaseAnalytics. All event names are defined here so
/// they never drift between call sites. Call these from viewmodels and views —
/// never from model classes.
class AnalyticsService {
  static final _a = FirebaseAnalytics.instance;

  static Future<void> logExerciseAdded(String exercise) =>
      _a.logEvent(name: 'exercise_added', parameters: {'exercise': exercise});

  static Future<void> logSetLogged(String exercise) =>
      _a.logEvent(name: 'set_logged', parameters: {'exercise': exercise});

  static Future<void> logSessionStarted() =>
      _a.logEvent(name: 'session_started');

  static Future<void> logCsvImported(int count) =>
      _a.logEvent(name: 'csv_imported', parameters: {'sets': count});

  static Future<void> logPaywallShown(String source) =>
      _a.logEvent(name: 'paywall_shown', parameters: {'source': source});

  static Future<void> logSubscriptionStarted(String plan) =>
      _a.logEvent(name: 'subscription_started', parameters: {'plan': plan});

  static Future<void> logCloudRetrain() =>
      _a.logEvent(name: 'cloud_retrain');

  static Future<void> logStreakMilestone(int days) =>
      _a.logEvent(name: 'streak_milestone', parameters: {'days': days});

  static Future<void> logOnboardingCompleted() =>
      _a.logEvent(name: 'onboarding_completed');
}
