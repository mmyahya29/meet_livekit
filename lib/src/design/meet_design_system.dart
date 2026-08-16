import 'dart:ui';
import 'package:flutter/material.dart';

class MeetColors {
  static const Color primary = Color(0xFFA4CD32);
  static const Color primaryDark = Color(0xFF6F8C1D);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceElevated = Color(0xFF2A2D34);
  static const Color background = Color(0xFF121212);
  static const Color outline = Color(0xFF2C2C2C);
  static const Color onSurface = Colors.white;
  static const Color onSurfaceVariant = Color(0xFFB0B0B0);
  static const Color error = Color(0xFFFF5252);
}

class MeetRadius {
  static const double sm = 12;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 28;
  static const double full = 999;
}

class MeetShadows {
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2),
  ];
}

class MeetGlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double blur;
  final Color? tintColor;
  final Border? border;

  const MeetGlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.blur = 20,
    this.tintColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(MeetRadius.md),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tintColor ?? Colors.white.withValues(alpha: 0.05),
            borderRadius: borderRadius ?? BorderRadius.circular(MeetRadius.md),
            border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class MeetBouncyTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleFactor;
  final Curve curve;

  const MeetBouncyTap({
    super.key,
    required this.child,
    this.onTap,
    this.scaleFactor = 0.95,
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<MeetBouncyTap> createState() => _MeetBouncyTapState();
}

class _MeetBouncyTapState extends State<MeetBouncyTap> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleFactor)
        .animate(CurvedAnimation(parent: _controller, curve: widget.curve));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(_) => _controller.forward();
  void _handleTapUp(_) => _controller.reverse();
  void _handleTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: widget.onTap != null ? _handleTapDown : null,
        onTapUp: widget.onTap != null ? _handleTapUp : null,
        onTapCancel: widget.onTap != null ? _handleTapCancel : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered && widget.onTap != null ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) => Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
