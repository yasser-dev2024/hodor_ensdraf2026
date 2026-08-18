import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.child, super.key});

  final Widget child;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _introController;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;
  late final Animation<double> _contentOpacity;
  late final Animation<Offset> _contentSlide;

  bool _showSplash = true;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _logoOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0, 0.55, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0, 0.72, curve: Curves.easeOutCubic),
      ),
    );
    _contentOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.35, 1, curve: Curves.easeOut),
    );
    _contentSlide =
        Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _introController,
            curve: const Interval(0.3, 1, curve: Curves.easeOutCubic),
          ),
        );
    _playSplash();
  }

  Future<void> _playSplash() async {
    await _introController.forward();
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() => _isExiting = true);
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          AnimatedOpacity(
            opacity: _isExiting ? 0 : 1,
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeInOutCubic,
            onEnd: () {
              if (_isExiting && mounted) {
                setState(() => _showSplash = false);
              }
            },
            child: const _SplashArtwork(),
          ),
      ],
    );
  }
}

class _SplashArtwork extends StatelessWidget {
  const _SplashArtwork();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_SplashScreenState>()!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.navy,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
        color: AppColors.navy,
        child: Semantics(
          label: 'وزارة التعليم، نظام الحضور الصباحي',
          container: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLandscape = constraints.maxWidth > constraints.maxHeight;
              final compact = constraints.maxHeight < 650;
              final logoWidth = isLandscape
                  ? (constraints.maxWidth * 0.2).clamp(170.0, 235.0)
                  : (constraints.maxWidth * 0.56).clamp(190.0, 275.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/attendance_splash_bg.png',
                    fit: BoxFit.cover,
                    alignment: isLandscape
                        ? Alignment.centerRight
                        : Alignment.bottomCenter,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppColors.navy),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.34, 0.7, 1],
                        colors: [
                          Color(0xF2153A5B),
                          Color(0xB8153A5B),
                          Color(0x26153A5B),
                          Color(0xD9153A5B),
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: isLandscape
                            ? const Alignment(0.65, -0.3)
                            : const Alignment(0, -0.2),
                        radius: 0.95,
                        colors: const [Color(0x244FD2B6), Colors.transparent],
                      ),
                    ),
                  ),
                  SafeArea(
                    minimum: EdgeInsets.symmetric(
                      horizontal: isLandscape ? 42 : 24,
                      vertical: compact ? 14 : 24,
                    ),
                    child: Column(
                      children: [
                        ScaleTransition(
                          scale: state._logoScale,
                          child: FadeTransition(
                            opacity: state._logoOpacity,
                            child: Container(
                              width: logoWidth,
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 15 : 18,
                                vertical: compact ? 10 : 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.78),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33081E31),
                                    blurRadius: 28,
                                    offset: Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/ministry_of_education_logo.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 12 : 20),
                        FadeTransition(
                          opacity: state._contentOpacity,
                          child: SlideTransition(
                            position: state._contentSlide,
                            child: Column(
                              children: [
                                Text(
                                  'نظام الحضور الصباحي',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 23 : 30,
                                    height: 1.35,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.4,
                                    shadows: const [
                                      Shadow(
                                        color: Color(0x66071B2B),
                                        blurRadius: 16,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'تحضير أسرع • متابعة أوضح',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.86),
                                    fontSize: compact ? 12 : 14,
                                    height: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        FadeTransition(
                          opacity: state._contentOpacity,
                          child: _LoadingPill(compact: compact),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 17,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xC6153A5B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x66FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF6CE0C3),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'تهيئة بيانات المدرسة',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
