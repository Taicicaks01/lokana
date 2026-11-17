// Lokana Cube: semua mood bisa digambar & dianimasikan tanpa galat, termasuk saat animasi dimatikan.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lokana/cube.dart';
import 'package:lokana/theme.dart';

void main() {
  testWidgets('ukuran mengikuti proporsi casing (35 × 36,7 mm)', (tester) async {
    final s = LokanaCube.sizeFor(1);
    expect(s.width, 140);
    expect(s.height, closeTo(146.8, 0.01));
    await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr, child: Center(child: LokanaCube(scale: 0.5))));
    expect(tester.getSize(find.byType(LokanaCube)), LokanaCube.sizeFor(0.5));
  });

  for (final reduce in [false, true]) {
    testWidgets('semua mood digambar (animasi ${reduce ? 'mati' : 'nyala'})', (tester) async {
      var mood = CubeMood.idle;
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.instance.data(Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: StatefulBuilder(builder: (c, s) {
            set = s;
            return Center(child: LokanaCube(mood: mood));
          }),
        ),
      ));
      for (final m in CubeMood.values) {
        set(() => mood = m);
        // lewati transisi mood, kedip pertama, dan beberapa siklus lirik/pantul
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 180));
        }
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel(RegExp('Lokana')), findsOneWidget);
      }
    });
  }

  testWidgets('CubeCheer: tersenyum sebentar lalu kembali', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.instance.data(Brightness.dark),
      home: const Center(child: LokanaCube(mood: CubeMood.mengantuk)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    CubeCheer.now();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));   // 650 ms senang + transisi kembali
    }
    expect(tester.takeException(), isNull);
  });
}
