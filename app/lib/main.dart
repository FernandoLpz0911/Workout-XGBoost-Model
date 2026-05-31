import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/rest_timer.dart';
import 'viewmodels/log_viewmodel.dart';
import 'views/log_view.dart';
import 'views/history_view.dart';
import 'views/progress_view.dart';
import 'views/settings_view.dart';

void main() {
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
        title: 'AI Workout',
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
        home: const _AppShell(),
      ),
    );
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
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
              const Text('Rest Timer',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        timer.start();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(timer.isRunning ? 'Restart' : 'Start'),
                    ),
                  ),
                  if (timer.isRunning) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          timer.stop();
                        },
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
