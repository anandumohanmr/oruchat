import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'utils.dart';

// ---- Colour matrix helpers (4x5 matrices, ColorFilter.matrix format) ----

const List<double> _identity = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
];

/// a after b
List<double> _mul(List<double> a, List<double> b) {
  final r = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      var s = 0.0;
      for (var k = 0; k < 4; k++) {
        s += a[i * 5 + k] * b[k * 5 + j];
      }
      if (j == 4) s += a[i * 5 + 4];
      r[i * 5 + j] = s;
    }
  }
  return r;
}

List<double> _chain(List<List<double>> steps) {
  var m = _identity;
  for (final s in steps) {
    m = _mul(s, m);
  }
  return m;
}

List<double> _sat(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return [
    sr + s, sg, sb, 0, 0, //
    sr, sg + s, sb, 0, 0, //
    sr, sg, sb + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

List<double> _contrast(double c) {
  final t = 128 * (1 - c);
  return [
    c, 0, 0, 0, t, //
    0, c, 0, 0, t, //
    0, 0, c, 0, t, //
    0, 0, 0, 1, 0,
  ];
}

List<double> _bright(double b) => [
  1, 0, 0, 0, b, //
  0, 1, 0, 0, b, //
  0, 0, 1, 0, b, //
  0, 0, 0, 1, 0,
];

List<double> _tint(
  double r,
  double g,
  double b, [
  double or = 0,
  double og = 0,
  double ob = 0,
]) => [
  r, 0, 0, 0, or, //
  0, g, 0, 0, og, //
  0, 0, b, 0, ob, //
  0, 0, 0, 1, 0,
];

class PhotoFilter {
  const PhotoFilter(this.name, this.matrix);
  final String name;
  final List<double> matrix;
}

final List<PhotoFilter> kFilters = [
  const PhotoFilter('Original', _identity),
  PhotoFilter('Mono', _sat(0)),
  PhotoFilter('Noir', _chain([_sat(0), _contrast(1.4)])),
  const PhotoFilter('Sepia', [
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  PhotoFilter(
    'Vintage',
    _chain([_sat(0.7), _contrast(0.9), _tint(1.1, 1.0, 0.8, 10, 5, 0)]),
  ),
  PhotoFilter('Warm', _tint(1.12, 1.02, 0.88)),
  PhotoFilter('Cool', _tint(0.9, 1.0, 1.15)),
  PhotoFilter('Vivid', _chain([_sat(1.6), _contrast(1.1)])),
  PhotoFilter('Fade', _chain([_sat(0.8), _contrast(0.8), _bright(20)])),
  const PhotoFilter('Invert', [
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0,
  ]),
  const PhotoFilter('Polaroid', [
    1.438, -0.062, -0.062, 0, 0, //
    -0.122, 1.378, -0.122, 0, 0, //
    -0.016, -0.016, 1.483, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  PhotoFilter(
    'Kodak',
    _chain([_tint(1.15, 1.05, 0.9), _sat(1.2), _contrast(1.1)]),
  ),
  PhotoFilter('Techni', _chain([_sat(1.5), _tint(1.1, 0.95, 1.1)])),
  PhotoFilter(
    'Lomo',
    _chain([_contrast(1.3), _sat(1.2), _tint(1.1, 1.0, 0.9, 0, 0, 8)]),
  ),
  PhotoFilter('Sunset', _tint(1.2, 0.95, 0.8, 15, 0, -10)),
  PhotoFilter('Ocean', _chain([_tint(0.8, 1.0, 1.2), _sat(1.2)])),
  PhotoFilter('Forest', _tint(0.9, 1.15, 0.85)),
  PhotoFilter('Rose', _tint(1.15, 0.9, 1.0, 10, 0, 5)),
  PhotoFilter('Dream', _chain([_tint(1.05, 0.9, 1.2), _bright(10), _sat(1.1)])),
  PhotoFilter('Bright', _chain([_bright(35), _contrast(1.05)])),
  PhotoFilter('Dark', _chain([_bright(-35), _contrast(1.1)])),
  PhotoFilter('Contrast', _contrast(1.6)),
  PhotoFilter(
    'Cyber',
    _chain([_tint(0.8, 1.1, 1.3), _contrast(1.2), _sat(1.5)]),
  ),
  PhotoFilter('Drama', _chain([_sat(0.7), _contrast(1.5)])),
  PhotoFilter('Mint', _tint(0.9, 1.1, 1.05, 0, 10, 10)),
  PhotoFilter('Peach', _chain([_tint(1.1, 1.0, 0.95, 20, 10, 0), _sat(1.1)])),
  PhotoFilter(
    'Gloom',
    _chain([_sat(0.5), _tint(0.9, 0.95, 1.1), _contrast(1.2)]),
  ),
];

/// Filter apply cheythu PNG aakki tharum.
Future<Uint8List> bakeFilter(Uint8List bytes, List<double> matrix) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..colorFilter = ColorFilter.matrix(matrix);
  canvas.drawImage(img, ui.Offset.zero, paint);
  final picture = recorder.endRecording();
  final out = await picture.toImage(img.width, img.height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw Exception('Could not apply filter');
  return data.buffer.asUint8List();
}

class EditResult {
  EditResult(this.bytes, this.isPng, this.caption);
  final Uint8List bytes;
  final bool isPng;
  final String? caption;
}

Future<EditResult?> editImage(
  BuildContext context,
  Uint8List bytes, {
  String actionLabel = 'Send',
  bool askCaption = true,
}) {
  return Navigator.of(context).push<EditResult>(
    MaterialPageRoute(
      builder: (_) => ImageEditPage(
        bytes: bytes,
        actionLabel: actionLabel,
        askCaption: askCaption,
      ),
      fullscreenDialog: true,
    ),
  );
}

class ImageEditPage extends StatefulWidget {
  const ImageEditPage({
    super.key,
    required this.bytes,
    this.actionLabel = 'Send',
    this.askCaption = true,
  });

  final Uint8List bytes;
  final String actionLabel;
  final bool askCaption;

  @override
  State<ImageEditPage> createState() => _ImageEditPageState();
}

class _ImageEditPageState extends State<ImageEditPage> {
  int selected = 0;
  bool busy = false;
  final caption = TextEditingController();

  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    setState(() => busy = true);
    final cap = caption.text.trim().isEmpty ? null : caption.text.trim();
    try {
      if (selected == 0) {
        Navigator.of(context).pop(EditResult(widget.bytes, false, cap));
        return;
      }
      final out = await bakeFilter(widget.bytes, kFilters[selected].matrix);
      if (!mounted) return;
      Navigator.of(context).pop(EditResult(out, true, cap));
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        snack(context, 'Could not apply the filter: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(kFilters[selected].name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: busy ? null : _done,
              style: FilledButton.styleFrom(backgroundColor: purple),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(widget.actionLabel),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(kFilters[selected].matrix),
                child: Image.memory(widget.bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          if (widget.askCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: TextField(
                controller: caption,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add a caption…',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white12,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 104,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: kFilters.length,
                itemBuilder: (context, i) {
                  final f = kFilters[i];
                  final isSel = i == selected;
                  return GestureDetector(
                    onTap: busy ? null : () => setState(() => selected = i),
                    child: Container(
                      width: 72,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? purple : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ColorFiltered(
                                colorFilter: ColorFilter.matrix(f.matrix),
                                child: Image.memory(
                                  widget.bytes,
                                  width: 66,
                                  height: 66,
                                  fit: BoxFit.cover,
                                  cacheWidth: 140,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSel ? Colors.white : Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
