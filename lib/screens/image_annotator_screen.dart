import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../models/app_settings.dart';
import '../models/note.dart';
import '../theme/byepasser_theme.dart';

enum _AnnotatorTool { marker, pins }

class _AnnotationPoint {
  final double x;
  final double y;

  const _AnnotationPoint(this.x, this.y);

  Offset toOffset() => Offset(x, y);
}

class _AnnotationStroke {
  final List<_AnnotationPoint> points;
  final Color color;

  const _AnnotationStroke({required this.points, required this.color});
}

class _AnnotationPin {
  final int id;
  final int number;
  final _AnnotationPoint position;
  final Color color;
  final String body;

  const _AnnotationPin({
    required this.id,
    required this.number,
    required this.position,
    required this.color,
    required this.body,
  });

  _AnnotationPin copyWith({
    _AnnotationPoint? position,
    int? number,
    Color? color,
    String? body,
  }) {
    return _AnnotationPin(
      id: id,
      number: number ?? this.number,
      position: position ?? this.position,
      color: color ?? this.color,
      body: body ?? this.body,
    );
  }
}

Future<bool> openImageAnnotator(BuildContext context, String imagePath) async {
  final result = await Navigator.of(context).push<bool>(
    CupertinoPageRoute(
      builder: (_) => ImageAnnotatorScreen(imagePath: imagePath),
    ),
  );
  if (result == true) {
    await FileImage(File(imagePath)).evict();
  }
  return result ?? false;
}

class ImageAnnotatorScreen extends StatefulWidget {
  final String imagePath;

  const ImageAnnotatorScreen({super.key, required this.imagePath});

  @override
  State<ImageAnnotatorScreen> createState() => _ImageAnnotatorScreenState();
}

class _ImageAnnotatorScreenState extends State<ImageAnnotatorScreen> {
  final _exportKey = GlobalKey();
  final _stageKey = GlobalKey();
  final _palette = const <Color>[
    Color(0xffe8775f),
    Color(0xff6a9bd6),
    Color(0xff7aaa90),
    Color(0xff9b8bc6),
    Color(0xff222222),
    Color(0xffffffff),
  ];

  _AnnotatorTool _tool = _AnnotatorTool.marker;
  Color _color = const Color(0xffe8775f);
  List<_AnnotationStroke> _strokes = const [];
  List<_AnnotationPoint>? _activeStroke;
  List<_AnnotationPin> _pins = const [];
  int _nextPinId = 0;
  int? _draggingPinIndex;
  DateTime? _pinTapStartedAt;
  bool _saving = false;
  final Map<int, TextEditingController> _pinBodyControllers = {};

  @override
  void dispose() {
    for (final controller in _pinBodyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        middle: const Text('Annotate'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : Text('Save', style: TextStyle(color: colors.accent)),
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final imageHeight = constraints.maxHeight * 0.5;
            return Column(
              children: [
                SizedBox(
                  height: imageHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: RepaintBoundary(
                      key: _exportKey,
                      child: Container(
                        decoration: colors.cardDecoration(radius: 18),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _buildStage(colors),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SingleChildScrollView(child: _buildToolbar(colors)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStage(ByepasserColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _tool == _AnnotatorTool.pins ? _beginPinTap : null,
          onTapUp: _tool == _AnnotatorTool.pins ? _addPin : null,
          onTapCancel: _tool == _AnnotatorTool.pins
              ? () => _pinTapStartedAt = null
              : null,
          onPanStart: _tool == _AnnotatorTool.marker ? _startStroke : null,
          onPanUpdate: _tool == _AnnotatorTool.marker ? _appendStroke : null,
          onPanEnd: _tool == _AnnotatorTool.marker
              ? (_) => _commitStroke()
              : null,
          onPanCancel: _tool == _AnnotatorTool.marker ? _cancelStroke : null,
          child: Stack(
            key: _stageKey,
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: colors.cardAlt,
                child: Image.file(
                  File(widget.imagePath),
                  width: width,
                  height: height,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      CupertinoIcons.photo,
                      color: colors.textSecondary,
                      size: 46,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _AnnotationPainter(
                    strokes: [
                      ..._strokes,
                      if (_activeStroke != null)
                        _AnnotationStroke(
                          points: _activeStroke!,
                          color: _color,
                        ),
                    ],
                  ),
                ),
              ),
              for (var i = 0; i < _pins.length; i++)
                Positioned(
                  left: _pins[i].position.x - 17,
                  top: _pins[i].position.y - 17,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) {
                      HapticFeedback.mediumImpact();
                      setState(() => _draggingPinIndex = i);
                    },
                    onPanUpdate: (details) =>
                        _movePin(i, details.globalPosition),
                    onPanEnd: (_) => setState(() => _draggingPinIndex = null),
                    onPanCancel: () => setState(() => _draggingPinIndex = null),
                    onDoubleTap: () => _removePin(_pins[i].id),
                    child: _PinMarker(
                      number: _pins[i].number,
                      color: _pins[i].color,
                      active: _draggingPinIndex == i,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(ByepasserColors colors) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: colors.cardDecoration(radius: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _ToolButton(
                label: 'Marker',
                icon: CupertinoIcons.pencil,
                active: _tool == _AnnotatorTool.marker,
                onTap: () => setState(() => _tool = _AnnotatorTool.marker),
              ),
              const SizedBox(width: 8),
              _ToolButton(
                label: 'Pins',
                icon: CupertinoIcons.number_circle,
                active: _tool == _AnnotatorTool.pins,
                onTap: () => setState(() => _tool = _AnnotatorTool.pins),
              ),
              const Spacer(),
              _IconAction(icon: CupertinoIcons.arrow_uturn_left, onTap: _undo),
              const SizedBox(width: 6),
              _IconAction(icon: CupertinoIcons.trash, onTap: _clear),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              final dotSize = compact ? 24.0 : 28.0;
              final gap = compact ? 6.0 : 8.0;
              return Row(
                children: [
                  for (final color in _palette) ...[
                    GestureDetector(
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: dotSize,
                        height: dotSize,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == color
                                ? colors.textPrimary
                                : colors.divider,
                            width: _color == color ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                  ],
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      _tool == _AnnotatorTool.pins
                          ? 'Tap to pin. Drag to move.'
                          : 'Drag to mark.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (_pins.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPinReferenceFields(colors),
          ],
        ],
      ),
    );
  }

  Widget _buildPinReferenceFields(ByepasserColors colors) {
    final textTheme = Theme.of(context).textTheme;
    final sortedPins = List<_AnnotationPin>.from(_pins)
      ..sort((a, b) => a.number.compareTo(b.number));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 168),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        padding: EdgeInsets.zero,
        itemCount: sortedPins.length,
        onReorder: _reorderPins,
        itemBuilder: (context, index) {
          final pin = sortedPins[index];
          final bodyController = _pinBodyController(pin);
          return Padding(
            key: ValueKey('annotation-pin-note-${pin.id}'),
            padding: EdgeInsets.only(
              bottom: index == sortedPins.length - 1 ? 0 : 8,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              decoration: BoxDecoration(
                color: colors.cardAlt.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${pin.number}.',
                      style: textTheme.labelLarge?.copyWith(
                        color: pin.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CupertinoTextField(
                      controller: bodyController,
                      placeholder: 'Cross-reference note',
                      minLines: 1,
                      maxLines: 3,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 8,
                      ),
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                      decoration: const BoxDecoration(),
                      onChanged: (value) =>
                          _updatePinReference(pin.id, body: value),
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(
                        CupertinoIcons.line_horizontal_3,
                        color: colors.textSecondary,
                        size: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Offset? _stageLocalFromGlobal(Offset global) {
    final box = _stageKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    return Offset(
      local.dx.clamp(0, box.size.width),
      local.dy.clamp(0, box.size.height),
    );
  }

  void _startStroke(DragStartDetails details) {
    final point = _stageLocalFromGlobal(details.globalPosition);
    if (point == null) return;
    HapticFeedback.selectionClick();
    setState(() => _activeStroke = [_AnnotationPoint(point.dx, point.dy)]);
  }

  void _appendStroke(DragUpdateDetails details) {
    final point = _stageLocalFromGlobal(details.globalPosition);
    if (point == null || _activeStroke == null) return;
    setState(() {
      _activeStroke = [..._activeStroke!, _AnnotationPoint(point.dx, point.dy)];
    });
  }

  void _commitStroke() {
    final active = _activeStroke;
    if (active == null) return;
    setState(() {
      if (active.length > 1) {
        _strokes = [
          ..._strokes,
          _AnnotationStroke(points: active, color: _color),
        ];
      }
      _activeStroke = null;
    });
  }

  void _cancelStroke() {
    setState(() => _activeStroke = null);
  }

  void _beginPinTap(TapDownDetails details) {
    _pinTapStartedAt = DateTime.now();
  }

  void _addPin(TapUpDetails details) {
    final startedAt = _pinTapStartedAt;
    _pinTapStartedAt = null;
    if (startedAt == null ||
        DateTime.now().difference(startedAt) >
            const Duration(milliseconds: 360)) {
      return;
    }
    HapticFeedback.selectionClick();
    final position = details.localPosition;
    final number = _pins.length + 1;
    setState(() {
      _pins = [
        ..._pins,
        _AnnotationPin(
          id: _nextPinId,
          number: number,
          position: _AnnotationPoint(position.dx, position.dy),
          color: _color,
          body: '',
        ),
      ];
      _nextPinId++;
    });
  }

  void _movePin(int index, Offset global) {
    final point = _stageLocalFromGlobal(global);
    if (point == null || index < 0 || index >= _pins.length) return;
    setState(() {
      final next = List<_AnnotationPin>.from(_pins);
      next[index] = next[index].copyWith(
        position: _AnnotationPoint(point.dx, point.dy),
      );
      _pins = next;
    });
  }

  void _updatePinReference(int pinId, {String? body}) {
    setState(() {
      _pins = [
        for (final pin in _pins)
          if (pin.id == pinId) pin.copyWith(body: body) else pin,
      ];
    });
  }

  void _reorderPins(int oldIndex, int newIndex) {
    setState(() {
      final ordered = List<_AnnotationPin>.from(_pins)
        ..sort((a, b) => a.number.compareTo(b.number));
      var targetIndex = newIndex;
      if (targetIndex > oldIndex) targetIndex -= 1;
      if (oldIndex < 0 ||
          oldIndex >= ordered.length ||
          targetIndex < 0 ||
          targetIndex >= ordered.length) {
        return;
      }
      final moved = ordered.removeAt(oldIndex);
      ordered.insert(targetIndex, moved);
      _pins = [
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(number: i + 1),
      ];
    });
  }

  TextEditingController _pinBodyController(_AnnotationPin pin) {
    return _pinBodyControllers.putIfAbsent(
      pin.id,
      () => TextEditingController(text: pin.body),
    );
  }

  void _disposePinControllers(int pinId) {
    _pinBodyControllers.remove(pinId)?.dispose();
  }

  void _syncPinControllers() {
    for (final pin in _pins) {
      final controller = _pinBodyControllers[pin.id];
      if (controller != null && controller.text != pin.body) {
        controller.text = pin.body;
      }
    }
    _prunePinControllers();
  }

  void _prunePinControllers() {
    final activeIds = _pins.map((pin) => pin.id).toSet();
    final removedIds = _pinBodyControllers.keys
        .where((id) => !activeIds.contains(id))
        .toList();
    for (final id in removedIds) {
      _disposePinControllers(id);
    }
  }

  void _clearPinControllers() {
    for (final controller in _pinBodyControllers.values) {
      controller.dispose();
    }
    _pinBodyControllers.clear();
  }

  void _removePin(int pinId) {
    setState(() {
      final next = List<_AnnotationPin>.from(_pins)
        ..removeWhere((pin) => pin.id == pinId);
      _pins = [
        for (var i = 0; i < next.length; i++) next[i].copyWith(number: i + 1),
      ];
      _disposePinControllers(pinId);
      _syncPinControllers();
    });
  }

  void _undo() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_tool == _AnnotatorTool.pins && _pins.isNotEmpty) {
        _pins = List<_AnnotationPin>.from(_pins)..removeLast();
        _prunePinControllers();
        return;
      }
      if (_strokes.isNotEmpty) {
        _strokes = List<_AnnotationStroke>.from(_strokes)..removeLast();
      } else if (_pins.isNotEmpty) {
        _pins = List<_AnnotationPin>.from(_pins)..removeLast();
        _prunePinControllers();
      }
    });
  }

  void _clear() {
    HapticFeedback.lightImpact();
    setState(() {
      _strokes = const [];
      _activeStroke = null;
      _pins = const [];
      _nextPinId = 0;
      _clearPinControllers();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _exportKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
        throw StateError('Image layout not ready');
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Could not encode annotation');
      await File(widget.imagePath).writeAsBytes(data.buffer.asUint8List());
      await _syncCrossReferenceNotes();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save annotation')),
      );
    }
  }

  Future<void> _syncCrossReferenceNotes() async {
    if (!Hive.isBoxOpen('notes') || !Hive.isBoxOpen('settings')) return;
    final notesBox = Hive.box<Note>('notes');
    final settingsBox = Hive.box<AppSettings>('settings');
    final settings = settingsBox.get('user') ?? AppSettings.defaults();
    final imagePath = widget.imagePath;
    final owner = _findAttachmentOwner(notesBox, imagePath);
    final boardId = owner?.boardId ?? settings.selectedBoardId;
    final lifetimeMinutes =
        owner?.lifetimeMinutes ?? settings.defaultLifetimeMinutes;
    final expiresAt =
        owner?.expiresAt ??
        DateTime.now().add(Duration(minutes: lifetimeMinutes));
    final colorTag = owner?.colorTag ?? settings.accentIndex;

    final pins = List<_AnnotationPin>.from(_pins)
      ..sort((a, b) => a.number.compareTo(b.number));
    final activeNumbers = pins.map((pin) => pin.number).toSet();
    final existing = notesBox.values
        .where((note) => note.crossReferenceImagePath == imagePath)
        .toList();

    for (final note in existing) {
      final pinNumber = note.crossReferencePinNumber;
      if (pinNumber == null || !activeNumbers.contains(pinNumber)) {
        await notesBox.put(
          note.id,
          note.copyWith(
            attachmentPaths: const [],
            deletedAt: DateTime.now(),
            orderIndex: 0,
          ),
        );
      }
    }

    for (final pin in pins) {
      final body = _numberedCrossReferenceBody(pin.number, pin.body);
      final matches = existing
          .where((note) => note.crossReferencePinNumber == pin.number)
          .toList();
      final match = matches.isEmpty ? null : matches.first;
      if (match == null) {
        final note = Note.create(
          title: null,
          body: body,
          lifetimeMinutes: lifetimeMinutes,
          isSteamMode: false,
          colorTag: colorTag,
          attachmentPaths: const [],
          boardId: boardId,
          crossReferenceImagePath: imagePath,
          crossReferencePinNumber: pin.number,
        ).copyWith(expiresAt: expiresAt, orderIndex: pin.number);
        await notesBox.put(note.id, note);
      } else {
        await notesBox.put(
          match.id,
          match.copyWith(
            title: null,
            body: body,
            expiresAt: expiresAt,
            lifetimeMinutes: lifetimeMinutes,
            colorTag: colorTag,
            attachmentPaths: const [],
            boardId: boardId,
            deletedAt: null,
            orderIndex: pin.number,
            crossReferenceImagePath: imagePath,
            crossReferencePinNumber: pin.number,
          ),
        );
      }
    }
  }

  Note? _findAttachmentOwner(Box<Note> notesBox, String imagePath) {
    final owners =
        notesBox.values
            .where(
              (note) =>
                  !note.isDeleted &&
                  !note.isImageCrossReference &&
                  note.attachmentPaths.contains(imagePath),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return owners.isEmpty ? null : owners.first;
  }
}

String _numberedCrossReferenceBody(int pinNumber, String body) {
  final trimmed = body.trim();
  return trimmed.isEmpty ? '$pinNumber.' : '$pinNumber. $trimmed';
}

class _AnnotationPainter extends CustomPainter {
  final List<_AnnotationStroke> strokes;

  const _AnnotationPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}

class _PinMarker extends StatelessWidget {
  final int number;
  final Color color;
  final bool active;

  const _PinMarker({
    required this.number,
    required this.color,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: active ? 1.12 : 1,
      child: SizedBox(
        width: 34,
        height: 34,
        child: CustomPaint(
          painter: _PinMarkerPainter(number: number, color: color),
        ),
      ),
    );
  }
}

class _PinMarkerPainter extends CustomPainter {
  final int number;
  final Color color;

  const _PinMarkerPainter({required this.number, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(center.translate(0, 3), radius - 2, shadowPaint);

    canvas.drawCircle(center, radius - 1.5, Paint()..color = color);
    canvas.drawCircle(
      center,
      radius - 1.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.center);
    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w800,
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText('$number');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: size.width));
    canvas.drawParagraph(
      paragraph,
      Offset(0, center.dy - paragraph.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PinMarkerPainter oldDelegate) {
    return oldDelegate.number != number || oldDelegate.color != color;
  }
}

class _ToolButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ToolButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: active ? colors.accent : colors.cardAlt,
        foregroundColor: active ? colors.textOnAccent : colors.textPrimary,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<ByepasserColors>()!;
    return SizedBox.square(
      dimension: 38,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        color: colors.textSecondary,
        padding: EdgeInsets.zero,
      ),
    );
  }
}
