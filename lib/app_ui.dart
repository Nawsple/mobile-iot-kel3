import 'package:flutter/material.dart';

/// Warna tema: butter yellow lembut + indikator merah/hijau/abu.
class AppColors {
  static const butter = Color(0xFFFFF4C2); // latar halaman
  static const butterDeep = Color(0xFFFFE89A); // app bar
  static const cream = Color(0xFFFFFCEB); // isi kotak
  static const border = Color(0xFFEBD98B); // garis kotak
  static const ink = Color(0xFF3B3320); // teks utama
  static const inkSoft = Color(0xFF7A6F4F); // teks sekunder
  static const gold = Color(0xFFF5C84C); // tombol utama
  static const goldDark = Color(0xFFC9961A); // fokus input

  static const okFg = Color(0xFF2E7D32);
  static const okBg = Color(0xFFE1F3DE);
  static const errFg = Color(0xFFC62828);
  static const errBg = Color(0xFFFBE0DC);
  static const idleFg = Color(0xFF6B6B6B);
  static const idleBg = Color(0xFFEAEAEA);
  static const busyFg = Color(0xFFB26A00);
  static const busyBg = Color(0xFFFFE7B0);
}

/// idle = abu-abu, busy = oranye (proses), ok = hijau, error = merah
enum ConnState { idle, busy, ok, error }

Color stateFg(ConnState s) {
  if (s == ConnState.ok) return AppColors.okFg;
  if (s == ConnState.error) return AppColors.errFg;
  if (s == ConnState.busy) return AppColors.busyFg;
  return AppColors.idleFg;
}

Color stateBg(ConnState s) {
  if (s == ConnState.ok) return AppColors.okBg;
  if (s == ConnState.error) return AppColors.errBg;
  if (s == ConnState.busy) return AppColors.busyBg;
  return AppColors.idleBg;
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.gold),
    scaffoldBackgroundColor: AppColors.butter,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.border,
        disabledForegroundColor: AppColors.inkSoft,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.goldDark),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

InputDecoration appInput({
  required String label,
  required IconData icon,
  Widget? suffix,
}) {
  final base = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  );
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    border: base,
    enabledBorder: base,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.goldDark, width: 2),
    ),
  );
}

/// Kotak status berwarna (abu / oranye / hijau / merah) dengan ikon.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.text, required this.state});

  final String text;
  final ConnState state;

  @override
  Widget build(BuildContext context) {
    final fg = stateFg(state);
    final Widget leading;
    if (state == ConnState.busy) {
      leading = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
      );
    } else if (state == ConnState.ok) {
      leading = Icon(Icons.check_circle, color: fg);
    } else if (state == ConnState.error) {
      leading = Icon(Icons.error, color: fg);
    } else {
      leading = Icon(Icons.radio_button_unchecked, color: fg);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: stateBg(state),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg, width: 1.2),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kotak putih-krem dengan judul dan ikon.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final IconData? icon;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: AppColors.goldDark),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// Kotak angka besar untuk data sensor.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.butter,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(height: 6),
          Text(
            '$value $unit',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.inkSoft)),
        ],
      ),
    );
  }
}

/// Lencana kecil berwarna (mis. online / offline).
class PillBadge extends StatelessWidget {
  const PillBadge({super.key, required this.text, required this.state});

  final String text;
  final ConnState state;

  @override
  Widget build(BuildContext context) {
    final fg = stateFg(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: stateBg(state),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tampilan kosong (belum ada hasil scan, dsb.)
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.border),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}