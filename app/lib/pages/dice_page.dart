import 'package:material_ui/material_ui.dart';
import '../link/link.dart';
import '../link/proto.dart';
import '../main.dart';

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
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < diceTypes.length; i++)
            ChoiceChip(label: Text(diceTypes[i]), selected: type == i, onSelected: (_) => setState(() => type = i)),
        ]),
        const SizedBox(height: 24),
        Card(
          color: cs.secondaryContainer,
          child: SizedBox(
            height: 140,
            child: Center(
              child: last == null
                  ? Text('Belum ada lemparan', style: t.titleMedium)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(last.text, style: t.displaySmall?.copyWith(color: cs.onSecondaryContainer)),
                      Text(last.typeName, style: t.bodyMedium),
                    ]),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => sendWithFeedback(context, T.dice, pDice(type)),
          icon: const Icon(Icons.casino),
          label: Text('Lempar ${diceTypes[type]}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        Text('Lemparan dari tombol Lokana juga muncul di sini.', style: t.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (link.dice.length > 1) Text('Riwayat', style: t.titleSmall),
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
