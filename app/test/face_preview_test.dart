// Pratinjau ekspresi = geometri face.cpp. Dibandingkan dengan tangkapan asli firmware 0.5.4 (2026-11-17):
// bentuk cocok; di sini dicek posisi kunci supaya perubahan tidak sengaja ketahuan.
import 'package:flutter_test/flutter_test.dart';
import 'package:lokana/face_preview.dart';
import 'package:lokana/link/proto.dart';

void main() {
  testWidgets('13 ekspresi digambar, ciri khas tiap wajah ada', (tester) async {
    final f = <Bitmap1>[];
    await tester.runAsync(() async {
      for (var i = 0; i < expressions.length; i++) {
        f.add(await expressionFace(i));
      }
    });
    int lit(Bitmap1 b) => [for (var y = 0; y < 64; y++) for (var x = 0; x < 128; x++) if (b.get(x, y)) 1].length;
    for (var i = 0; i < expressions.length; i++) {
      expect(lit(f[i]), greaterThan(80), reason: 'ekspresi $i kosong');
    }
    // netral: pusat kedua mata menyala (mata kiri ±x 37, kanan ±x 91, y 29)
    expect(f[0].get(37, 29) && f[0].get(91, 29), isTrue);
    // senang: bagian bawah mata dipotong pipi (mata senyum)
    expect(f[1].get(37, 40), isFalse);
    // ngantuk: z/Z di kanan atas
    expect([for (var y = 10; y < 32; y++) for (var x = 106; x < 128; x++) f[4].get(x, y)].contains(true), isTrue);
    // kedip: mata kiri terbuka penuh, mata kanan tinggal lengkungan
    expect(f[12].get(37, 29), isTrue);
    expect(lit(f[12]), lessThan(lit(f[0])));
    // pusing: pusat spiral tidak terisi penuh seperti mata netral
    expect(lit(f[7]), lessThan(lit(f[0])));
  });
}
