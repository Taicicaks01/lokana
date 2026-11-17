import 'package:material_ui/material_ui.dart';
import '../link/proto.dart';
import '../main.dart';
import '../ui.dart';

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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('Ekspresi')),
      body: PageBody(children: [
        Text('Ketuk ekspresi untuk ditampilkan di wajah Lokana.',
            style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          children: [
            for (var i = 0; i < expressions.length; i++)
              Card(
                color: last == i ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    setState(() => last = i);
                    await sendWithFeedback(context, T.expression, pExpression(i, holdMs: (holdS * 1000).round()));
                  },
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(expressions[i].$2, style: const TextStyle(fontSize: 36)),
                    const SizedBox(height: 4),
                    Text(expressions[i].$1),
                  ]),
                ),
              ),
          ],
        ),
      ]),
    );
  }
}
