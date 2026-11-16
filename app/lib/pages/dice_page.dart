import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';
import '../ui.dart';

/// DICE: lempar dari HP; hasil dari Lokana (termasuk lemparan dari tombol) muncul di sini.
class DicePage extends StatefulWidget {
  const DicePage({super.key});

  @override
  State<DicePage> createState() => _DicePageState();
}

class _DicePageState extends State<DicePage> {
  final link = LokanaLink.instance;
  int type = 0;

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    link.addListener(_changed);
  }

  @override
  void dispose() {
    link.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final last = link.dice.isEmpty ? null : link.dice.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Dadu')),
      bottomNavigationBar: ActionBar(
        label: 'Lempar ${diceTypes[type]}',
        icon: Icons.casino_rounded,
        onPressed: () => sendWithFeedback(context, T.dice, pDice(type)),
      ),
      body: PageBody(children: [
        Card(
          color: cs.secondaryContainer,
          child: SizedBox(
            height: 160,
            child: Center(
              child: last == null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.casino_outlined, size: 40, color: cs.onSecondaryContainer),
                      const SizedBox(height: Gap.s),
                      Text('Belum ada lemparan', style: t.titleMedium?.copyWith(color: cs.onSecondaryContainer)),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(last.text, style: t.displaySmall?.copyWith(color: cs.onSecondaryContainer)),
                      Text(last.typeName, style: t.bodyMedium?.copyWith(color: cs.onSecondaryContainer)),
                    ]),
            ),
          ),
        ),
        const SizedBox(height: Gap.s),
        Text('Lemparan dari sentuhan di Lokana juga muncul di sini.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
        const SectionHeader('Jenis dadu', icon: Icons.category_outlined),
        Panel(children: [
          Choices<int>(
            options: {for (var i = 0; i < diceTypes.length; i++) i: diceTypes[i]},
            value: type,
            onChanged: (v) => setState(() => type = v),
          ),
        ]),
        if (link.dice.length > 1) const SectionHeader('Riwayat', icon: Icons.history),
        for (final r in link.dice.skip(1))
          ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text(r.text),
            subtitle: Text(r.typeName),
            trailing: Text('${r.at.hour.toString().padLeft(2, '0')}:${r.at.minute.toString().padLeft(2, '0')}'
                ':${r.at.second.toString().padLeft(2, '0')}'),
          ),
      ]),
    );
  }
}
