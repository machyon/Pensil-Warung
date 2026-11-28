import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Splash "00c" from the Design canvas. Pure look; `SplashGate` decides when to leave.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  static const _ink = Color(0xFF1B1B19);
  static const _paper = Color(0xFFF3F2F1);

  // Entrance: logo, wordmark and dots rise in with 0.2s stagger, 0.6s each.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..forward();

  // Dots: one 1.2s loop; each dot lags the previous by 0.15s.
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _dots.dispose();
    super.dispose();
  }

  Widget _rise(double start, double end, Widget child) {
    final t = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, end, curve: Curves.easeOut),
    );
    return AnimatedBuilder(
      animation: t,
      builder: (context, content) => Transform.translate(
        offset: Offset(0, (1 - t.value) * 10),
        child: Opacity(opacity: t.value, child: content),
      ),
      child: child,
    );
  }

  // Keyframes from the design: 0% 0.6 / 40% 1 / 80% 0.6, then rest.
  double _dotLevel(double phase) {
    if (phase < 0.4) return 0.6 + 0.4 * (phase / 0.4);
    if (phase < 0.8) return 1 - 0.4 * ((phase - 0.4) / 0.4);
    return 0.6;
  }

  Widget _dot(int index, bool reduceMotion) {
    return AnimatedBuilder(
      animation: _dots,
      builder: (context, _) {
        final level = reduceMotion ? 1.0 : _dotLevel((_dots.value - index * 0.125) % 1.0);
        return Transform.scale(
          scale: level,
          child: Opacity(
            opacity: reduceMotion ? 1 : 0.35 + 0.65 * ((level - 0.6) / 0.4),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(4)),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: _paper,
      body: Semantics(
        label: 'Pensil Warung sedang dimuat',
        liveRegion: true,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _rise(0, 0.6, SvgPicture.asset(
                'assets/images/logo_pensil_warung.svg',
                width: 64,
                height: 64,
                excludeFromSemantics: true,
              )),
              const SizedBox(height: 16),
              _rise(0.2, 0.8, Text(
                'Pensil Warung',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: _ink,
                ),
              )),
              const SizedBox(height: 28),
              _rise(0.4, 1, ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _dot(i, reduceMotion),
                    ],
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
