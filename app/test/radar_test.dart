// Radar ketinggalan: pemetaan RSSI ke jarak & label, dan semua keadaan bisa digambar.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lokana/radar.dart';
import 'package:lokana/theme.dart';

void main() {
  test('RSSI -> jarak 0..1 dan label', () {
    expect(LeaveRadar.distance(-45), 0);
    expect(LeaveRadar.distance(-70), 0.5);
    expect(LeaveRadar.distance(-95), 1);
    expect(radarLabel(-58), 'Dekat · −58 dBm');
    expect(radarLabel(-72), 'Agak jauh · −72 dBm');
    expect(radarLabel(-88), 'Jauh · −88 dBm');
    expect(radarLabel(null), 'Tidak ada sinyal');
  });

  for (final reduce in [false, true]) {
    testWidgets('radar dekat, jauh, terputus (animasi ${reduce ? 'mati' : 'nyala'})', (tester) async {
      int? rssi = -55;
      late StateSetter set;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.instance.data(Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: StatefulBuilder(builder: (c, s) {
            set = s;
            return Center(child: LeaveRadar(rssi: rssi));
          }),
        ),
      ));
      for (final r in [-55, -85, null, -60]) {
        set(() => rssi = r);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}
