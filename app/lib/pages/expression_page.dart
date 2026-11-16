import 'package:material_ui/material_ui.dart';
import '../link/proto.dart';
import '../main.dart';

class ExpressionPage extends StatefulWidget {
  const ExpressionPage({super.key});

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
      appBar: AppBar(title: const Text('Ekspresi')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Ketuk ekspresi untuk ditampilkan di Lokana.', style: t.bodyMedium),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 0; i < expressions.length; i++)
              Card(
                color: last == i ? Theme.of(context).colorScheme.primaryContainer : null,
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
        const SizedBox(height: 24),
        Text('Lama ditahan: ${holdS.round()} detik', style: t.titleSmall),
        Slider(value: holdS, min: 1, max: 30, divisions: 29, label: '${holdS.round()} dtk',
            onChanged: (v) => setState(() => holdS = v)),
      ]),
    );
  }
}
