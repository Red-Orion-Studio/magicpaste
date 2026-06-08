// MagicPaste design tokens + reusable glassmorphism widgets.
// Recreated from the Claude Design handoff (glassmorphism, electric-violet).

import 'dart:ui';

import 'package:flutter/material.dart';

/// Design tokens (mirror the `MP` object in the design's magicpaste-screens.jsx).
class MP {
  static const violet = Color(0xFF7C3AED);
  static const violetLight = Color(0xFFA78BFA);
  static const white = Color(0xFFFFFFFF);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);

  static const base = Color(0xFF0D0D0F);
  static const glass = Color(0x12FFFFFF); // rgba(255,255,255,0.07)
  static const glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSec = Color(0x99FFFFFF); // 0.60
  static const textMuted = Color(0x59FFFFFF); // 0.35

  /// Radial-gradient + base background used on every screen.
  static const BoxDecoration scaffoldBg = BoxDecoration(
    color: base,
    gradient: RadialGradient(
      center: Alignment(-0.56, -0.64),
      radius: 1.1,
      colors: [Color(0x387C3AED), Color(0x000D0D0F)],
      stops: [0.0, 0.52],
    ),
  );

  /// Second radial accent (bottom-right indigo) painted as an overlay layer.
  static const BoxDecoration scaffoldBgOverlay = BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(0.56, 0.64),
      radius: 1.1,
      colors: [Color(0x246366F1), Color(0x000D0D0F)],
      stops: [0.0, 0.52],
    ),
  );
}

/// Full-screen background (two stacked radial gradients over the base color).
class MpBackground extends StatelessWidget {
  final Widget child;
  const MpBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: MP.scaffoldBg,
      child: DecoratedBox(
        decoration: MP.scaffoldBgOverlay,
        child: child,
      ),
    );
  }
}

enum GlassGlow { none, green, red, violet }

/// Frosted-glass card with optional colored glow border.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final GlassGlow glow;
  final double radius;
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.glow = GlassGlow.none,
    this.radius = 20,
  });

  ({Color border, List<BoxShadow> shadows}) get _glowStyle {
    switch (glow) {
      case GlassGlow.green:
        return (
          border: const Color(0x5222C55E),
          shadows: const [
            BoxShadow(color: Color(0x2122C55E), blurRadius: 36),
            BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(0, 8)),
          ],
        );
      case GlassGlow.red:
        return (
          border: const Color(0x52EF4444),
          shadows: const [
            BoxShadow(color: Color(0x21EF4444), blurRadius: 36),
            BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(0, 8)),
          ],
        );
      case GlassGlow.violet:
        return (
          border: const Color(0x667C3AED),
          shadows: const [
            BoxShadow(color: Color(0x337C3AED), blurRadius: 36),
            BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(0, 8)),
          ],
        );
      case GlassGlow.none:
        return (
          border: MP.glassBorder,
          shadows: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 8)),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _glowStyle;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: style.shadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: MP.glass,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: style.border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// App logo: violet gradient circle with a clipboard + green check glyph.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: const [BoxShadow(color: Color(0x8C7C3AED), blurRadius: 18, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/img/logo.png', fit: BoxFit.cover),
    );
  }
}

/// Small uppercase section label (violet, letter-spaced).
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xA6A78BFA),
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class GlassDivider extends StatelessWidget {
  const GlassDivider({super.key});
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0x12FFFFFF), child: SizedBox(height: 1, width: double.infinity));
}
