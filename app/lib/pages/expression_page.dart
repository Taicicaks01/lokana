import 'package:material_ui/material_ui.dart';
import '../face_preview.dart';
import '../link/proto.dart';
import '../main.dart';
import '../render.dart';
import '../theme.dart';
import '../ui.dart';

/// EXPRESSION: pilih raut wajah Lokana. Pratinjau = wajah asli Lokana (geometri face.cpp), bukan emoji.
class ExpressionPage extends StatefulWidget {
  /// true = tampil di dalam tab (tanpa AppBar sendiri; judul dari tab).
  final bool embedded;
  const ExpressionPage({super.key, this.embedded = false});

  @override
  State<ExpressionPage> createState() => _ExpressionPageState();
}

class _ExpressionPageState extends State<ExpressionPage> {
  double holdS = 4;
  int? last;
  List<Anim1>? faces;

  @override
  void initState() {
    super.initState();
    Future.wait([for (var i = 0; i < expressions.length; i++) expressionFace(i)]).then((list) {
      if (mounted) setState(() => faces = [for (final b in list) Anim1(128, 64, [b])]);
    });
  }

  static String _label(String id) => id[0].toUpperCase() + id.substring(1);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lk = context.lk;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Ekspresi')),
      body: PageBody(children: [
        Text('Ketuk ekspresi untuk ditampilkan di wajah Lokana.', style: t.bodyMedium?.copyWith(color: lk.muted)),
        const SizedBox(height: Gap.l),
        Panel(children: [
          Field('Lama ditahan: ${holdS.round()} detik', first: true,
              help: 'Setelah itu Lokana kembali ke ekspresi biasanya.',
              child: Slider(value: holdS, min: 1, max: 30, divisions: 29, label: '${holdS.round()} dtk',
                  onChanged: (v) => setState(() => holdS = v))),
        ]),
        const SizedBox(height: Gap.l),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.95,
          children: [
            for (var i = 0; i < expressions.length; i++)
              Card(
                color: last == i ? lk.pinkSoft : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: last == i ? cs.primary : lk.line, width: last == i ? 2 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    setState(() => last = i);
                    await sendWithFeedback(context, T.expression, pExpression(i, holdMs: (holdS * 1000).round()));
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [
                      Expanded(
                        child: faces == null
                            ? DecoratedBox(
                                decoration: BoxDecoration(color: lk.surface2, borderRadius: BorderRadius.circular(8)))
                            : OledPreview(anim: faces![i]),
                      ),
                      const SizedBox(height: 6),
                      Text(_label(expressions[i].$1),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelLarge?.copyWith(
                              color: last == i ? cs.primary : null, fontWeight: last == i ? FontWeight.w700 : null)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}
