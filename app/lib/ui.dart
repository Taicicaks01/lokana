// Komponen UI bersama Aplikasi Lokana: kerangka halaman, bagian (section), pilihan, bilah aksi bawah,
// kartu fitur, dan "mata" Lokana. Semua halaman memakai ini supaya tampilan konsisten.
import 'dart:math';
import 'package:material_ui/material_ui.dart';

/// Jarak standar.
class Gap {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;
}

/// Isi halaman yang bisa digulir, lebar maksimum 640 (rapi di tablet), dengan ruang untuk bilah aksi.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const PageBody({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24)});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: padding, children: children),
        ),
      );
}

/// Judul bagian dengan ikon kecil, deskripsi opsional, dan aksi di kanan.
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.icon, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xl, bottom: Gap.s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (icon != null) ...[Icon(icon, size: 20, color: cs.primary), const SizedBox(width: Gap.s)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium),
            if (subtitle != null) Text(subtitle!, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Kartu berisi sekelompok pengaturan.
class Panel extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  final Color? color;
  const Panel({super.key, required this.children, this.padding = const EdgeInsets.all(16), this.color});

  @override
  Widget build(BuildContext context) => Card(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

/// Label + keterangan + kontrol di dalam Panel.
class Field extends StatelessWidget {
  final String label;
  final String? help;
  final Widget child;
  final bool first;
  const Field(this.label, {super.key, this.help, required this.child, this.first = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : Gap.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: t.labelLarge),
        if (help != null) ...[
          const SizedBox(height: 2),
          Text(help!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: Gap.s),
        child,
      ]),
    );
  }
}

/// Deretan pilihan (chip). [enabled] false = abu-abu.
class Choices<T> extends StatelessWidget {
  final Map<T, String> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final Map<T, TextStyle>? styles;
  const Choices({super.key, required this.options, required this.value, this.onChanged, this.styles});

  @override
  Widget build(BuildContext context) => Wrap(spacing: Gap.s, runSpacing: Gap.s, children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value, style: styles?[e.key]),
            selected: value == e.key,
            onSelected: onChanged == null ? null : (_) => onChanged!(e.key),
          ),
      ]);
}

/// Bilah aksi di bawah layar (selalu terlihat): tombol utama besar, aksi kedua opsional, progres.
class ActionBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Widget? secondary;
  final double? progress;   // null = tidak sedang mengirim
  final String? note;
  const ActionBar({super.key, required this.label, required this.icon, this.onPressed, this.secondary, this.progress,
      this.note});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (progress != null)
            LinearProgressIndicator(value: progress == 0 ? null : progress, minHeight: 3)
          else
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(note!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                    ),
                  Row(children: [
                    if (secondary != null) ...[secondary!, const SizedBox(width: Gap.s)],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: progress != null ? null : onPressed,
                        icon: Icon(icon),
                        label: Text(label),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ikon di kotak membulat berwarna lembut.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color, background;
  final double size;
  const IconBadge(this.icon, {super.key, this.color, this.background, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background ?? cs.primaryContainer, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, size: size * 0.55, color: color ?? cs.onPrimaryContainer),
    );
  }
}

/// Kartu fitur di beranda: ikon, judul, keterangan singkat.
class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool highlight;
  const FeatureCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap,
      this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      color: highlight ? cs.tertiaryContainer : cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconBadge(icon,
                size: 40,
                background: highlight ? cs.tertiary : cs.primaryContainer,
                color: highlight ? cs.onTertiary : cs.onPrimaryContainer),
            const Spacer(),
            Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

/// Baris menu: ikon, judul, keterangan, panah.
class NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  const NavRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: IconBadge(icon, size: 38),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
      );
}

/// Kotak info / peringatan kecil.
class Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool warning;
  final Widget? action;
  const Notice(this.text, {super.key, this.icon = Icons.info_outline, this.warning = false, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = warning ? cs.errorContainer : cs.secondaryContainer;
    final fg = warning ? cs.onErrorContainer : cs.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, size: 20, color: fg),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg))),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ]),
    );
  }
}

/// Label status kecil (contoh: "Tersambung", "v0.5.3").
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  const Pill(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Wajah Lokana (dua mata OLED) yang berkedip pelan. Dipakai di beranda & halaman sambung.
class LokanaEyes extends StatefulWidget {
  final Color color;
  final double height;
  final bool sleepy;
  const LokanaEyes({super.key, required this.color, this.height = 56, this.sleepy = false});

  @override
  State<LokanaEyes> createState() => _LokanaEyesState();
}

class _LokanaEyesState extends State<LokanaEyes> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      height: widget.height,
      child: AspectRatio(
        aspectRatio: 2.2,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            // kedip singkat di akhir putaran
            final t = _c.value;
            var open = widget.sleepy ? 0.12 : 1.0;
            if (!reduce && !widget.sleepy && t > 0.93) open = (cos((t - 0.93) / 0.07 * 2 * pi) + 1) / 2 * 0.9 + 0.1;
            return CustomPaint(painter: _EyesPainter(widget.color, open));
          },
        ),
      ),
    );
  }
}

class _EyesPainter extends CustomPainter {
  final Color color;
  final double open;
  _EyesPainter(this.color, this.open);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final ew = size.width * 0.34, eh = size.height * 0.9 * open, gap = size.width * 0.12;
    final x0 = (size.width - ew * 2 - gap) / 2, y = (size.height - eh) / 2;
    final r = Radius.circular(min(ew, size.height * 0.9) * 0.28);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x0, y, ew, eh), r), p);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x0 + ew + gap, y, ew, eh), r), p);
  }

  @override
  bool shouldRepaint(_EyesPainter old) => old.open != open || old.color != color;
}

/// Tampilkan pesan singkat di bawah layar.
void showSnack(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
