import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/services/notification_service.dart';
import 'package:repiq/services/rest_timer.dart';
import 'package:repiq/viewmodels/log_viewmodel.dart';
import 'package:repiq/views/history_view.dart';
import 'package:repiq/views/log_view.dart';
import 'package:repiq/views/onboarding_view.dart';
import 'package:repiq/views/progress_view.dart';
import 'package:repiq/views/settings_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(const WorkoutApp());
}

class WorkoutApp extends StatelessWidget {
  const WorkoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LogViewModel()),
        ChangeNotifierProvider(create: (_) => RestTimer()),
      ],
      child: MaterialApp(
        title: 'RepIQ',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.dark(
            primary: Colors.redAccent,
            secondary: Colors.blueAccent,
            surface: const Color(0xFF262730),
          ),
          scaffoldBackgroundColor: const Color(0xFF0E1117),
          cardColor: const Color(0xFF262730),
          useMaterial3: true,
        ),
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool? _done;

  @override
  void initState() {
    super.initState();
    isOnboardingDone().then((v) { if (mounted) setState(() => _done = v); });
  }

  @override
  Widget build(BuildContext context) {
    if (_done == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0E1117),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_done!) {
      return OnboardingView(onComplete: () => setState(() => _done = true));
    }
    return const _AppShell();
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _index = 0;

  static const _titles = ['Log Workout', 'History', 'Progress', 'Settings'];

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.fitness_center_outlined),
      selectedIcon: Icon(Icons.fitness_center),
      label: 'Log',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: 'History',
    ),
    NavigationDestination(
      icon: Icon(Icons.show_chart_outlined),
      selectedIcon: Icon(Icons.show_chart),
      label: 'Progress',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  static const _pages = [
    LogView(),
    HistoryView(),
    ProgressView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        backgroundColor: const Color(0xFF0E1117),
        surfaceTintColor: Colors.transparent,
        actions: const [_TimerAction(), SizedBox(width: 8)],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
        backgroundColor: const Color(0xFF262730),
        indicatorColor: Colors.redAccent.withValues(alpha: 0.25),
      ),
    );
  }
}

class _TimerAction extends StatelessWidget {
  const _TimerAction();

  @override
  Widget build(BuildContext context) {
    return Consumer<RestTimer>(
      builder: (context, timer, _) {
        final isDone = !timer.isRunning && timer.remaining == 0;
        final isLow = timer.remaining > 0 && timer.remaining <= 10;
        final color = isLow ? Colors.redAccent : Colors.white;

        return TextButton.icon(
          onPressed: () => _showSheet(context, timer),
          icon: Icon(
            isDone ? Icons.timer_outlined : Icons.timer,
            color: color,
            size: 20,
          ),
          label: Text(
            isDone ? '' : timer.displayTime,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        );
      },
    );
  }

  void _showSheet(BuildContext context, RestTimer timer) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF262730),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: timer,
        child: const _TimerSheet(),
      ),
    );
  }
}

class _TimerSheet extends StatelessWidget {
  const _TimerSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<RestTimer>(
      builder: (context, timer, _) {
        final mq = MediaQuery.of(context);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + mq.padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Rest Timer',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SheetButton(
                      Icons.remove,
                      onPressed: () => timer.adjustSeconds(-15),
                    ),
                    const SizedBox(width: 24),
                    SizedBox(
                      width: 100,
                      child: Text(
                        timer.isRunning
                            ? timer.displayTime
                            : '${timer.totalSeconds ~/ 60}:${(timer.totalSeconds % 60).toString().padLeft(2, '0')}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: (timer.isRunning && timer.remaining <= 10)
                              ? Colors.redAccent
                              : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    _SheetButton(
                      Icons.add,
                      onPressed: () => timer.adjustSeconds(15),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${timer.totalSeconds}s total',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 4),
                _SettingCheck(
                  label: 'VIBRATE',
                  value: timer.vibrationEnabled,
                  onChanged: (v) => timer.vibrationEnabled = v,
                ),
                _SettingCheck(
                  label: 'SOUND',
                  value: timer.soundEnabled,
                  onChanged: (v) => timer.soundEnabled = v,
                ),
                _SettingCheck(
                  label: 'AUTO START',
                  value: timer.autoStartEnabled,
                  onChanged: (v) => timer.autoStartEnabled = v,
                ),
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Text(
                      'VOLUME',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w500,
                        color: timer.soundEnabled
                            ? Colors.grey
                            : Colors.grey[700],
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: timer.volume,
                        onChanged:
                            timer.soundEnabled ? (v) => timer.volume = v : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: timer.start,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(timer.isRunning ? 'Restart' : 'Start'),
                      ),
                    ),
                    if (timer.isRunning) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: timer.stop,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Stop'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _SheetButton(this.icon, {required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1C1C26),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }
}

class _SettingCheck extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingCheck(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v!),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
