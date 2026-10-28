import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:repiq/models/recommendation_models.dart';
import 'package:repiq/models/workout_set.dart';
import 'package:repiq/services/rest_timer.dart';
import 'package:repiq/services/units_controller.dart';
import 'package:repiq/theme/app_theme.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/log_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late LogViewModel vm;

  Future<void> pumpExercisePage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Skip the reminder-scheduling platform call that logSet would trigger.
    SharedPreferences.setMockInitialValues({
      'last_notif_day': LogViewModel.fmtDate(DateTime.now()),
    });
    await tester.runAsync(() async {
      vm = LogViewModel();
      while (vm.isDictLoading) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      vm.addExercise('Chest', 'Bench Press');
      // Let the async recommendation settle, then pin a known one.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      vm.session[0].recommendation = const Recommendation(
        targetReps: 8,
        targetWeight: 30,
        status: 'Test reason',
        predicted1RM: 40,
        required1RM: 38,
        notesInsight: '',
      );
      vm.session[0].recError = null;
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: vm),
          ChangeNotifierProvider(create: (_) => RestTimer()),
          ChangeNotifierProvider(create: (_) => UnitsController()),
        ],
        child: MaterialApp(
          theme: AppThemes.of(AppThemeId.midnight).data,
          home: const Scaffold(body: LogView()),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows TRACK, HISTORY and GRAPH tabs', (tester) async {
    await pumpExercisePage(tester);
    expect(find.widgetWithText(Tab, 'TRACK'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'HISTORY'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'GRAPH'), findsOneWidget);
    expect(find.text('Suggested: 30.0 lbs × 8'), findsOneWidget);
    expect(find.text('SAVE'), findsOneWidget);
    expect(find.text('CLEAR'), findsOneWidget);
  });

  testWidgets('Use fills the steppers with the suggestion', (tester) async {
    await pumpExercisePage(tester);
    // Move the reps stepper away from the suggestion, then press Use.
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    expect(find.text('9'), findsOneWidget);
    await tester.tap(find.text('Use'));
    await tester.pump();
    expect(find.text('8'), findsOneWidget);
    expect(find.text('30.0'), findsOneWidget);
  });

  testWidgets('logged sets are listed and tapping one switches to UPDATE', (
    tester,
  ) async {
    await pumpExercisePage(tester);
    await tester.runAsync(() async {
      for (final (i, w) in [(0, 30.0), (1, 35.0)]) {
        vm.logSet(
          0,
          WorkoutSet(
            date: DateTime.now().add(Duration(seconds: i)),
            exercise: 'Bench Press',
            category: 'Chest',
            weight: w,
            reps: 8,
          ),
        );
      }
    });
    await tester.pump();
    expect(find.text('30.0 lbs × 8'), findsWidgets);
    expect(find.text('35.0 lbs × 8'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('35.0 lbs × 8'));
    await tester.pump();
    expect(find.text('UPDATE'), findsOneWidget);
    expect(find.text('SAVE'), findsNothing);

    await tester.tap(find.text('CLEAR'));
    await tester.pump();
    expect(find.text('SAVE'), findsOneWidget);
  });
}
