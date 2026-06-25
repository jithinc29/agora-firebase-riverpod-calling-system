import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCreatePostTap;
  final VoidCallback onCreateReelTap;
  final bool isMenuOpen;
  final VoidCallback onMenuToggle;
  final VoidCallback onMenuClose;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onCreatePostTap,
    required this.onCreateReelTap,
    required this.isMenuOpen,
    required this.onMenuToggle,
    required this.onMenuClose,
  });

  @override
  State<CustomBottomNavBar> createState() => _CustomBottomNavBarState();
}

class _CustomBottomNavBarState extends State<CustomBottomNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.fastOutSlowIn,
      reverseCurve: Curves.easeInBack,
    );
    if (widget.isMenuOpen) {
      _animationController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant CustomBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMenuOpen != widget.isMenuOpen) {
      if (widget.isMenuOpen) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    widget.onMenuToggle();
  }

  void _closeMenu() {
    widget.onMenuClose();
  }

  @override
  Widget build(BuildContext context) {
    // Bubble end offsets relative to the center "+" button
    const double leftBubbleDx = -60.0;
    const double leftBubbleDy = -100.0;

    const double middleBubbleDx = 60.0;
    const double middleBubbleDy = -100.0;

    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          // Expand the Stack's bounds so the floating button is fully clickable
          const SizedBox(height: 100, width: double.infinity),

          // 1. Dim Overlay when menu is open (Blur removed for performance)
          if (widget.isMenuOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeMenu,
                behavior: HitTestBehavior.translucent,
                child: FadeTransition(
                  opacity: _expandAnimation,
                  child: Container(
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
              ),
            ),

          // 2. Liquid Gooey Connections (Drawn behind bubbles but in front of overlay)
          if (widget.isMenuOpen)
            Positioned(
              bottom: 56, // Center aligned with the floating "+" notch
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _expandAnimation,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(300, 200),
                      painter: GooeyBridgePainter(
                        progress: _expandAnimation.value,
                        leftBubbleTarget: const Offset(
                          leftBubbleDx,
                          leftBubbleDy,
                        ),
                        middleBubbleTarget: const Offset(
                          middleBubbleDx,
                          middleBubbleDy,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // 3. Popping Bubbles (Animated Positions)
          _buildBubble(
            icon: Icons.add_box_rounded, // Post
            dx: leftBubbleDx,
            dy: leftBubbleDy,
            onTap: () {
              _closeMenu();
              widget.onCreatePostTap();
            },
          ),
          _buildBubble(
            icon: Icons.slow_motion_video_rounded, // Reel
            dx: middleBubbleDx,
            dy: middleBubbleDy,
            onTap: () {
              _closeMenu();
              widget.onCreateReelTap();
            },
          ),

          // 4. Custom Floating Bottom Bar Container
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
            child: CustomPaint(
              size: const Size(double.infinity, 56),
              painter: BottomBarShadowPainter(),
              child: ClipPath(
                clipper: BottomBarClipper(),
                child: Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2E2252), Color(0xFF1E143F)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Tab 0: Feeds / Home
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _closeMenu();
                            widget.onTap(0);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.currentIndex == 0
                                    ? Icons.home
                                    : Icons.home_outlined,
                                color: widget.currentIndex == 0
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Tab 1: Chats
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _closeMenu();
                            widget.onTap(1);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.currentIndex == 1
                                    ? Icons.chat_bubble
                                    : Icons.chat_bubble_outline,
                                color: widget.currentIndex == 1
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Notch Spacer
                      const SizedBox(width: 80),
                      // Tab 2: Reels / Video Clips
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _closeMenu();
                            widget.onTap(2);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.currentIndex == 2
                                    ? Icons.play_circle
                                    : Icons.play_circle_outline,
                                color: widget.currentIndex == 2
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Tab 3: Profile / Settings
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _closeMenu();
                            widget.onTap(3);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.currentIndex == 3
                                    ? Icons.person
                                    : Icons.person_outline,
                                color: widget.currentIndex == 3
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 5. Central Floating "+" Button Nestled in notch
          Positioned(
            bottom: 30,
            child: GestureDetector(
              onTap: _toggleMenu,
              child: AnimatedBuilder(
                animation: _animationController,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFF43F5E),
                        Color(0xFFEC4899),
                      ], // Hot pink gradient
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.add, color: Colors.white, size: 32),
                  ),
                ),
                builder: (context, child) {
                  // Rotates the button 135 degrees (turns "+" into "x")
                  final angle = _animationController.value * math.pi * 0.75;
                  return Transform.rotate(angle: angle, child: child);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper builder for animated pop-up bubble buttons
  Widget _buildBubble({
    required IconData icon,
    required double dx,
    required double dy,
    required VoidCallback onTap,
  }) {
    return Positioned(
      bottom: 58, // Origin center aligned with notch center
      child: AnimatedBuilder(
        animation: _expandAnimation,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFF43F5E), Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(child: Icon(icon, color: Colors.white, size: 24)),
          ),
        ),
        builder: (context, child) {
          final t = _expandAnimation.value;
          // Calculate scale and position offset
          final double scale = t < 0.2 ? 0.0 : ((t - 0.2) / 0.8);
          final double curDx = dx * t;
          final double curDy = dy * t;

          if (t == 0.0) return const SizedBox.shrink();

          return Transform.translate(
            offset: Offset(curDx, curDy),
            child: Transform.scale(scale: scale, child: child),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Custom Path Clipper for the Bottom Navigation Bar Notch/Dip
// ----------------------------------------------------------------------
class BottomBarClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    // Top left rounded corner
    path.moveTo(0, 28);
    path.quadraticBezierTo(0, 0, 28, 0);

    // Notch start
    final double notchStart = w / 2 - 58;
    path.lineTo(notchStart, 0);

    // Smooth bezier notch
    final double notchCenter = w / 2;
    path.cubicTo(notchCenter - 28, 0, notchCenter - 34, 40, notchCenter, 40);
    path.cubicTo(notchCenter + 34, 40, notchCenter + 28, 0, w / 2 + 58, 0);

    // Top right rounded corner
    path.lineTo(w - 28, 0);
    path.quadraticBezierTo(w, 0, w, 28);

    // Bottom right rounded corner
    path.lineTo(w, h - 28);
    path.quadraticBezierTo(w, h, w - 28, h);

    // Bottom left rounded corner
    path.lineTo(28, h);
    path.quadraticBezierTo(0, h, 0, h - 28);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ----------------------------------------------------------------------
// Bottom Navigation Bar Shadow Painter
// ----------------------------------------------------------------------
class BottomBarShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final clipper = BottomBarClipper();
    final path = clipper.getClip(size);

    canvas.drawShadow(path, const Color(0xFF0F172A), 14, false);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ----------------------------------------------------------------------
// Custom Gooey/Liquid Strentch Bridge Painter
// ----------------------------------------------------------------------
class GooeyBridgePainter extends CustomPainter {
  final double progress;
  final Offset leftBubbleTarget;
  final Offset middleBubbleTarget;

  GooeyBridgePainter({
    required this.progress,
    required this.leftBubbleTarget,
    required this.middleBubbleTarget,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Bridges only stretch up to 60% of the movement, then snap!
    if (progress <= 0.0 || progress >= 0.6) return;

    final double bridgeT = progress / 0.6; // normalized 0.0 to 1.0
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF43F5E), Color(0xFFEC4899)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(-100, -150, 200, 200))
      ..style = PaintingStyle.fill;

    // Radii of the center and bubble circles
    const double rCenter = 30.0;
    const double rBubble = 22.0;

    _drawGooeyBridge(
      canvas,
      paint,
      const Offset(0, 0),
      leftBubbleTarget * progress,
      rCenter,
      rBubble,
      bridgeT,
    );
    _drawGooeyBridge(
      canvas,
      paint,
      const Offset(0, 0),
      middleBubbleTarget * progress,
      rCenter,
      rBubble,
      bridgeT,
    );
  }

  void _drawGooeyBridge(
    Canvas canvas,
    Paint paint,
    Offset cA,
    Offset cB,
    double rA,
    double rB,
    double t,
  ) {
    final double dx = cB.dx - cA.dx;
    final double dy = cB.dy - cA.dy;
    final double dist = math.sqrt(dx * dx + dy * dy);

    if (dist < 10) return;

    // Unit directions
    final double ux = dx / dist;
    final double uy = dy / dist;

    // Perpendicular vectors
    final double px = -uy;
    final double py = ux;

    // Tapering radii at the connection bridge
    final double rAeff = rA * (1.0 - t * 0.45);
    final double rBeff = rB * (1.0 - t * 0.70);

    // Tangent connection points on Circle A
    final Offset pA1 = Offset(cA.dx + rAeff * px, cA.dy + rAeff * py);
    final Offset pA2 = Offset(cA.dx - rAeff * px, cA.dy - rAeff * py);

    // Tangent connection points on Circle B
    final Offset pB1 = Offset(cB.dx + rBeff * px, cB.dy + rBeff * py);
    final Offset pB2 = Offset(cB.dx - rBeff * px, cB.dy - rBeff * py);

    // Midpoints
    final Offset mid1 = Offset((pA1.dx + pB1.dx) / 2, (pA1.dy + pB1.dy) / 2);
    final Offset mid2 = Offset((pA2.dx + pB2.dx) / 2, (pA2.dy + pB2.dy) / 2);

    // Inward control points to create liquid stretching neck effect
    final double pullBack = dist * 0.16 * t;
    final Offset ctrl1 = Offset(
      mid1.dx - pullBack * ux,
      mid1.dy - pullBack * uy,
    );
    final Offset ctrl2 = Offset(
      mid2.dx - pullBack * ux,
      mid2.dy - pullBack * uy,
    );

    final Path path = Path()
      ..moveTo(pA1.dx, pA1.dy)
      ..quadraticBezierTo(ctrl1.dx, ctrl1.dy, pB1.dx, pB1.dy)
      ..lineTo(pB2.dx, pB2.dy)
      ..quadraticBezierTo(ctrl2.dx, ctrl2.dy, pA2.dx, pA2.dy)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant GooeyBridgePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
