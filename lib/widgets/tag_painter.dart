import 'package:flutter/material.dart';

/// One box to draw: [rect] in 0..1 of the preview, a text tag and a colour.
class BoxTag {
  final Rect rect;
  final String text;
  final Color color;
  final double strokeWidth;
  const BoxTag(this.rect, this.text, this.color, {this.strokeWidth = 2.5});
}

/// Draws each box with its tag on a filled label above it.
class TagPainter extends CustomPainter {
  TagPainter(this.tags);
  final List<BoxTag> tags;

  /// Red (low) -> green (high) for a 0..1 score.
  static Color scoreColor(double s) => Color.lerp(Colors.red, Colors.greenAccent, s.clamp(0.0, 1.0))!;

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in tags) {
      final rect = Rect.fromLTRB(
          t.rect.left * size.width, t.rect.top * size.height, t.rect.right * size.width, t.rect.bottom * size.height);
      canvas.drawRect(rect, Paint()
        ..color = t.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = t.strokeWidth);
      if (t.text.isEmpty) continue;
      final tag = TextPainter(
        text: TextSpan(
            text: ' ${t.text} ',
            style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      final top = (rect.top - tag.height).clamp(0.0, size.height - tag.height);
      canvas.drawRect(Rect.fromLTWH(rect.left, top, tag.width, tag.height), Paint()..color = t.color);
      tag.paint(canvas, Offset(rect.left, top));
    }
  }

  @override
  bool shouldRepaint(TagPainter old) => old.tags != tags;
}
