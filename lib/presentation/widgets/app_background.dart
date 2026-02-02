import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF6F1E9),
            Color(0xFFE7F3F1),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(
              size: 180,
              color: const Color(0xFF0B6E99).withOpacity(0.15),
            ),
          ),
          Positioned(
            bottom: -70,
            left: -40,
            child: _Blob(
              size: 160,
              color: const Color(0xFFF2A65A).withOpacity(0.2),
            ),
          ),
          Positioned(
            top: 140,
            left: -30,
            child: _Blob(
              size: 110,
              color: const Color(0xFF0B6E99).withOpacity(0.1),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
