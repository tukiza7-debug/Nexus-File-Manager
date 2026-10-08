/// Splash — the Nexus mark assembles itself: soft glow blooms, the geometric
/// N scales in, the signature triangle node pulses node-by-node, the
/// wordmark rises. 1.5 s total, skippable with any key or click.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/nexus_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1500); // within 1.3–1.7 s

  late final AnimationController _nodeCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..forward();
  Timer? _exitTimer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _exitTimer = Timer(_duration, _finish);
    _nodeCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _exitTimer?.cancel();
    _nodeCtrl.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) {
      _finish();
    }
    return false;
  }

  void _finish() {
    if (_leaving || !mounted) return;
    _leaving = true;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? NexusColors.bgDark : NexusColors.bgLight;

    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient brand glow.
            Center(
              child: Container(
                width: 460,
                height: 460,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      (dark ? NexusColors.blue : NexusColors.blueSoft)
                          .withValues(alpha:  dark ? 0.16 : 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 700.ms, curve: Curves.easeOut),
            // Logo + node choreography.
            Center(
              child: SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SvgPicture.asset(
                      'assets/logo/nexus-logo-primary.svg',
                      colorFilter: dark
                          ? null
                          : const ColorFilter.mode(NexusColors.navy, BlendMode.srcIn),
                    )
                        .animate()
                        .fadeIn(duration: 420.ms, curve: Curves.easeOut)
                        .scale(
                            begin: const Offset(0.92, 0.92),
                            end: const Offset(1, 1),
                            duration: 520.ms,
                            curve: Curves.easeOutCubic),
                    CustomPaint(
                      painter: _NodePulsePainter(
                        progress: _nodeCtrl.value,
                        bright: !dark,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 260.ms, duration: 300.ms)
                        // Gentle lift-off sheen after the nodes connect.
                        .fadeOut(delay: 1050.ms, duration: 380.ms),
                  ],
                ),
              ),
            ),
            // Wordmark + tagline.
            Align(
              alignment: const Alignment(0, 0.32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nexus',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Powerful. Precise. Beautiful.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: 620.ms, duration: 420.ms, curve: Curves.easeOut)
                .moveY(begin: 14, end: 0, delay: 620.ms, duration: 460.ms, curve: Curves.easeOutCubic),
            // Loading hairline.
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 42),
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      value: _nodeCtrl.value.clamp(0, 1),
                      backgroundColor:
                          (dark ? NexusColors.borderDark : NexusColors.borderLight)
                              .withValues(alpha:  0.6),
                    ),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}

/// Pulses the three signature nodes in sequence, then draws the connecting
/// triangle lines between them. Coordinates mirror the official SVG.
class _NodePulsePainter extends CustomPainter {
  _NodePulsePainter({required this.progress, required this.bright});

  final double progress;
  final bool bright;

  // Node circle centres in the 512-viewBox space (translate(185,255) + offsets).
  static const _nodes = [
    Offset(185 + 0, 255 + 20),
    Offset(185 + 40, 255 + 0),
    Offset(185 + 40, 255 + 40),
  ];
  static const _edges = [(0, 1), (1, 2), (2, 0)];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512; // viewBox → widget scale
    final glow = Paint()
      ..color = NexusColors.blueSoft.withValues(alpha: 0.35 * (1 - progress))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    // Edges draw as progress crosses each phase.
    final edgePaint = Paint()
      ..color = bright ? NexusColors.blue : NexusColors.blueSoft
      ..strokeWidth = 3.0 * s
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < _edges.length; i++) {
      final t = ((progress - (0.30 + i * 0.14)) / 0.16).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final a = _nodes[_edges[i].$1] * s;
      final b = Offset.lerp(_nodes[_edges[i].$1] * s, _nodes[_edges[i].$2] * s, t)!;
      canvas.drawLine(a, b, edgePaint);
    }

    // Nodes pulse in staggered sequence.
    for (var i = 0; i < _nodes.length; i++) {
      final t = ((progress - (i * 0.16)) / 0.30).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final pulse = (t < 0.6 ? Curves.easeOutBack.transform(t / 0.6) : 1.0);
      final c = _nodes[i] * s;
      final r = 7.0 * s * pulse;
      canvas.drawCircle(c, r * 1.9, glow);
      canvas.drawCircle(c, r, Paint()..color = NexusColors.blueSoft);
    }
  }

  @override
  bool shouldRepaint(covariant _NodePulsePainter old) => old.progress != progress;
}
