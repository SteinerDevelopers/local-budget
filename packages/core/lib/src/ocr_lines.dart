/// Rebuilds visual text lines from OCR word boxes (e2-capture.md §3 v1.1).
///
/// ML Kit returns spatial *blocks*; on a receipt the label column and the
/// right-aligned amount column are often two blocks, so `TOTAL` and `$42.50`
/// — one visual line — arrive in separate strings and no anchor rule can
/// join them. The fix is at tier 1: regroup words by vertical center before
/// the heuristics ever see a line. PDF text layers and already-ordered
/// screenshots bypass this entirely.
class OcrWord {
  const OcrWord({
    required this.text,
    required this.centerX,
    required this.centerY,
    this.height = 20,
  });

  final String text;
  final double centerX;
  final double centerY;

  /// Glyph-box height; the clustering tolerance is half the median of these.
  final double height;
}

abstract final class OcrLineAssembly {
  /// Floor for the y-tolerance — tiny/blurry glyph boxes must not make every
  /// word its own line.
  static const double _minTolerance = 6;

  /// Words → visual lines, top-to-bottom; within a line, left-to-right.
  /// Pure and deterministic: no Flutter, no plugins, tier-1 testable.
  static List<String> assemble(List<OcrWord> words) {
    final usable = words.where((w) => w.text.trim().isNotEmpty).toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));
    if (usable.isEmpty) return const [];

    final heights = words.map((w) => w.height).toList()..sort();
    final tolerance = (heights[heights.length ~/ 2] / 2)
        .clamp(_minTolerance, double.infinity);

    final lines = <_LineCluster>[];
    for (final w in usable) {
      final last = lines.isEmpty ? null : lines.last;
      if (last != null && (w.centerY - last.centerY).abs() <= tolerance) {
        last.add(w);
      } else {
        lines.add(_LineCluster(w));
      }
    }
    return [for (final l in lines) l.join()];
  }
}

class _LineCluster {
  _LineCluster(OcrWord first)
      : _words = [first],
        _sum = first.centerY,
        centerY = first.centerY;

  final List<OcrWord> _words;
  double _sum;
  double centerY;

  void add(OcrWord w) {
    _words.add(w);
    _sum += w.centerY;
    // Running mean keeps drifting rows (a tilted receipt) on one line.
    centerY = _sum / _words.length;
  }

  String join() {
    _words.sort((a, b) => a.centerX.compareTo(b.centerX));
    return _words.map((w) => w.text.trim()).join(' ');
  }
}
