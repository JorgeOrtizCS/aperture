import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Displays a borrowed image in a bounded area. The caller owns the image.
class PngDocumentView extends StatelessWidget {
  const PngDocumentView({
    super.key,
    required this.image,
    required this.semanticLabel,
  });

  final ui.Image image;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      if (viewport.isEmpty) return const SizedBox.shrink();
      return _DocumentViewport(
        key: ValueKey((image, viewport)),
        viewport: viewport,
        image: image,
        semanticLabel: semanticLabel,
      );
    },
  );
}

class _DocumentViewport extends StatefulWidget {
  const _DocumentViewport({
    super.key,
    required this.viewport,
    required this.image,
    required this.semanticLabel,
  });

  final Size viewport;
  final ui.Image image;
  final String semanticLabel;

  @override
  State<_DocumentViewport> createState() => _DocumentViewportState();
}

class _DocumentViewportState extends State<_DocumentViewport> {
  static const _maxZoom = 5.0;
  static const _tapZoom = 2.5;
  static const _fitBarHeight = 48.0;
  late final Size _viewport = Size(
    widget.viewport.width,
    math.max(0, widget.viewport.height - _fitBarHeight),
  );
  late final Rect _page = Alignment.center.inscribe(
    applyBoxFit(
      BoxFit.contain,
      Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
      _viewport,
    ).destination,
    Offset.zero & _viewport,
  );
  late final _DocumentTransform _transform = _DocumentTransform(
    _viewport,
    _page,
  );
  Offset _tapPosition = Offset.zero;
  int _gestureGeneration = 0;

  void _setZoom(double scale, Offset focus) {
    final scenePoint = _transform.toScene(focus);
    final translation = focus - scenePoint * scale;
    _transform.value = Matrix4.diagonal3Values(scale, scale, scale)
      ..setEntry(0, 3, translation.dx)
      ..setEntry(1, 3, translation.dy);
    // Discard the old gesture recognizer and any pending fling.
    setState(() => _gestureGeneration++);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_viewport.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox.fromSize(
          size: _viewport,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: (details) => _tapPosition = details.localPosition,
            onDoubleTap: () => _setZoom(
              _transform.value.getMaxScaleOnAxis() > 1.01 ? 1 : _tapZoom,
              _tapPosition,
            ),
            child: InteractiveViewer(
              key: ValueKey(_gestureGeneration),
              transformationController: _transform,
              minScale: 1,
              maxScale: _maxZoom,
              // The controller constrains each axis to the fitted page.
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: Center(
                child: Semantics(
                  image: true,
                  label: widget.semanticLabel,
                  child: RawImage(
                    image: widget.image,
                    width: _page.width,
                    height: _page.height,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: _fitBarHeight,
          child: TextButton.icon(
            onPressed: () => _setZoom(1, _viewport.center(Offset.zero)),
            icon: const Icon(Icons.fit_screen_outlined),
            label: const Text('Fit to screen'),
          ),
        ),
      ],
    );
  }
}

/// Pin the image edges when the page overflows and center it on an axis when
/// the entire page fits. InteractiveViewer supplies pinch, pan and inertia.
class _DocumentTransform extends TransformationController {
  _DocumentTransform(this.viewport, this.page);

  final Size viewport;
  final Rect page;

  @override
  set value(Matrix4 matrix) {
    final scale = matrix.getMaxScaleOnAxis();
    matrix
      ..setEntry(
        0,
        3,
        _bound(
          matrix.entry(0, 3),
          page.left,
          page.right,
          viewport.width,
          scale,
        ),
      )
      ..setEntry(
        1,
        3,
        _bound(
          matrix.entry(1, 3),
          page.top,
          page.bottom,
          viewport.height,
          scale,
        ),
      );
    super.value = matrix;
  }

  double _bound(
    double translation,
    double start,
    double end,
    double extent,
    double scale,
  ) {
    final min = extent - end * scale;
    final max = -start * scale;
    // With equal edges, clamp can distinguish +0.0 from -0.0.
    return min < max ? translation.clamp(min, max) : (min + max) / 2;
  }
}
