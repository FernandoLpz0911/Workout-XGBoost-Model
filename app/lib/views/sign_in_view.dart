import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:repiq/viewmodels/auth_viewmodel.dart';

/// Full-screen sign-in screen shown when the user is not authenticated.
class SignInView extends StatelessWidget {
  const SignInView({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    return Scaffold(
      backgroundColor: const Color(0xFF0E1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const Icon(Icons.fitness_center, size: 72, color: Colors.redAccent),
              const SizedBox(height: 20),
              const Text(
                'Workout ML',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'AI-powered strength training',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 48),
              _FeatureRow(Icons.auto_awesome, 'Smart progression recommendations'),
              _FeatureRow(Icons.trending_up, 'Hypertrophy & strength modes'),
              _FeatureRow(Icons.notes, 'Form & fatigue analysis from your notes'),
              _FeatureRow(Icons.show_chart, 'Progress charts & 1RM tracking'),
              const Spacer(flex: 3),
              if (auth.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    auth.error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              _GoogleSignInButton(
                isLoading: auth.isSigningIn,
                onPressed: () => context.read<AuthViewModel>().signIn(),
              ),
              const SizedBox(height: 32),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () {},
                    child: const Text('Privacy Policy',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  const Text('·',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  TextButton(
                    onPressed: () {},
                    child: const Text('Terms of Service',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.redAccent, size: 18),
          ),
          const SizedBox(width: 16),
          Text(text, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;
  const _GoogleSignInButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Google 'G' logo colours
                  _GoogleG(),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF1F1F1F),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _GoogleG extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const colors = [
      Color(0xFF4285F4),
      Color(0xFF34A853),
      Color(0xFFFBBC05),
      Color(0xFFEA4335),
    ];
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 3.5;
    final cx = size.width / 2, cy = size.height / 2, r = size.width / 2 - 1;

    // Blue arc (right + top)
    paint.color = colors[0];
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -0.52, 3.14, false, paint);
    // Green (bottom-right)
    paint.color = colors[1];
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        2.62, 0.88, false, paint);
    // Yellow (bottom-left)
    paint.color = colors[2];
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -3.93, 0.88, false, paint);
    // Red (top-left)
    paint.color = colors[3];
    canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r),
        -3.14, 0.88, false, paint);

    // Horizontal bar
    paint
      ..color = colors[0]
      ..strokeWidth = 3.5;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(rect.right - 1, cy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
