import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Spacing scale shared by every screen. Pick from this list; never invent a
/// one-off gap.
class Insets {
  const Insets._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal page gutter on phones.
  static const double page = 20;
}

/// Corner radii. Larger surfaces get larger radii; controls stay tighter.
class Radii {
  const Radii._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// Durations and curves. Motion answers a touch or explains a change; it is
/// never decoration.
class Motion {
  const Motion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 480);

  static const Curve out = Curves.easeOutCubic;
  static const Curve inOut = Curves.easeInOutCubic;
  static const Curve spring = Curves.easeOutBack;
}

extension LifelogContext on BuildContext {
  LifelogPalette get palette => LifelogPalette.of(this);
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  /// Phone-width layout.
  bool get compact => MediaQuery.sizeOf(this).width < 600;

  /// Honours the platform's reduce-motion setting.
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
}

class AppTheme {
  const AppTheme._();

  // Brand seed. Everything else is hand-tuned below.
  static const seed = Color(0xFF4753D8);

  static const serifFamily = 'Georgia';
  static const serifFallback = <String>[
    'Cambria',
    'Noto Serif',
    'Times New Roman',
    'serif',
  ];

  /// Journal voice: used for titles, dates and anything the person wrote.
  static TextStyle serif(TextStyle? base, {double? size, FontWeight? weight}) {
    return (base ?? const TextStyle()).copyWith(
      fontFamily: serifFamily,
      fontFamilyFallback: serifFallback,
      fontSize: size,
      fontWeight: weight,
    );
  }

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;

    // Minimal, airy surfaces with a soft glass-like feel.
    final surface = dark ? const Color(0xFF0A0C12) : const Color(0xFFF4F5F8);
    final card = dark ? const Color(0xCC171A24) : const Color(0xE6FFFFFF);
    final subtle = dark ? const Color(0xFF161A26) : const Color(0xFFF0F2F7);
    final border = dark ? const Color(0x33FFFFFF) : const Color(0x140F172A);
    final ink = dark ? const Color(0xFFF2F4FA) : const Color(0xFF10131C);

    final primary = dark ? const Color(0xFFB4BCFF) : const Color(0xFF4C57D8);

    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xFF11142E) : Colors.white,
          primaryContainer: primary.withValues(alpha: dark ? 0.20 : 0.10),
          onPrimaryContainer: primary,
          secondary: dark ? const Color(0xFFF0C978) : const Color(0xFFB7770C),
          tertiary: dark ? const Color(0xFF78D8B0) : const Color(0xFF238863),
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: ink.withValues(alpha: 0.60),
          surfaceContainerLowest: surface,
          surfaceContainerLow: card,
          surfaceContainer: card,
          surfaceContainerHigh: subtle,
          surfaceContainerHighest: subtle,
          outline: dark ? const Color(0xFF4A5068) : const Color(0xFFBCC2D6),
          outlineVariant: border,
          error: dark ? const Color(0xFFFF909B) : const Color(0xFFD03A4A),
        );

    final palette = LifelogPalette(
      card: card,
      subtle: subtle,
      border: border,
      mutedText: ink.withValues(alpha: 0.58),
      dimText: ink.withValues(alpha: 0.38),
      journal: primary,
      tracker: scheme.tertiary,
      place: dark ? const Color(0xFF76C0EC) : const Color(0xFF2A84B8),
      music: dark ? const Color(0xFFC6A6FF) : const Color(0xFF8857D8),
      photo: dark ? const Color(0xFFF2BD72) : const Color(0xFFC87816),
      manual: dark ? const Color(0xFFAAB1CC) : const Color(0xFF6A7390),
      isDark: dark,
    );

    final text = _textTheme(scheme);

    RoundedRectangleBorder rounded(double r) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[palette],
      splashFactory: InkSparkle.splashFactory,
      splashColor: primary.withValues(alpha: 0.06),
      highlightColor: Colors.transparent,
      hoverColor: primary.withValues(alpha: 0.04),
      focusColor: primary.withValues(alpha: 0.10),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: primary.withValues(alpha: 0.24),
        selectionHandleColor: primary,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        centerTitle: false,
        titleTextStyle: AppTheme.serif(text.titleLarge, size: 20),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.72),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: ink.withValues(alpha: 0.40)),
        labelStyle: TextStyle(color: ink.withValues(alpha: 0.58)),
        border: _inputBorder(Colors.transparent),
        enabledBorder: _inputBorder(Colors.transparent),
        disabledBorder: _inputBorder(Colors.transparent),
        focusedBorder: _inputBorder(primary.withValues(alpha: 0.7), width: 1.4),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: rounded(Radii.lg),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          side: BorderSide(color: border),
          shape: rounded(Radii.lg),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: rounded(Radii.md),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: rounded(Radii.lg),
          side: BorderSide(color: border),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: subtle.withValues(alpha: dark ? 0.7 : 0.9),
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: ink.withValues(alpha: 0.82),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? const Color(0xFFA4AAC0) : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : (dark ? const Color(0xFF273043) : const Color(0xFFD7DBE7)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? const Color(0xF2161922) : const Color(0xF7FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: rounded(Radii.xl),
        titleTextStyle: AppTheme.serif(text.headlineSmall),
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xF2141720) : const Color(0xF7FFFFFF),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor:
            dark ? const Color(0xF2141720) : const Color(0xF7FFFFFF),
        modalBarrierColor:
            Colors.black.withValues(alpha: dark ? 0.55 : 0.28),
        showDragHandle: true,
        dragHandleColor: border.withValues(alpha: dark ? 0.6 : 0.35),
        dragHandleSize: const Size(38, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? const Color(0xF21A1E2A) : const Color(0xFAFFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: rounded(Radii.lg),
        textStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xF22A3042) : const Color(0xF21A1E2A),
        contentTextStyle:
            const TextStyle(color: Colors.white, fontSize: 13.5),
        actionTextColor: const Color(0xFFD6DBFF),
        insetPadding: const EdgeInsets.all(Insets.lg),
        shape: rounded(Radii.lg),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: rounded(Radii.xl),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: Insets.lg),
        minVerticalPadding: Insets.sm,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: subtle,
        circularTrackColor: subtle,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: dark ? const Color(0xF22A3042) : const Color(0xF21A1E2A),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(4),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(ink.withValues(alpha: 0.14)),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor:
            dark ? const Color(0xF2161922) : const Color(0xF7FFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: rounded(Radii.xl),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor:
            dark ? const Color(0xF2161922) : const Color(0xF7FFFFFF),
        shape: rounded(Radii.xl),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: LifelogPageTransitions(),
          TargetPlatform.windows: LifelogPageTransitions(),
          TargetPlatform.linux: LifelogPageTransitions(),
          TargetPlatform.fuchsia: LifelogPageTransitions(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final base = Typography.material2021(platform: defaultTargetPlatform);
    final t = (scheme.brightness == Brightness.dark ? base.white : base.black)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    TextStyle display(TextStyle? s, double size, double ls, double h) {
      return serif(s, size: size, weight: FontWeight.w600).copyWith(
        letterSpacing: ls,
        height: h,
      );
    }

    return t.copyWith(
      displayLarge: display(t.displayLarge, 48, -1.2, 1.05),
      displayMedium: display(t.displayMedium, 40, -1.0, 1.08),
      displaySmall: display(t.displaySmall, 34, -0.8, 1.1),
      headlineLarge: display(t.headlineLarge, 30, -0.6, 1.15),
      headlineMedium: display(t.headlineMedium, 27, -0.5, 1.15),
      headlineSmall: display(t.headlineSmall, 21, -0.2, 1.25),
      titleLarge: t.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: t.titleSmall?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14.5, height: 1.45),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12.5, height: 1.4),
      labelLarge: t.labelLarge?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: t.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: t.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
    );
  }
}

/// A short fade-and-rise for pushed pages. Skipped when the platform asks for
/// reduced motion.
class LifelogPageTransitions extends PageTransitionsBuilder {
  const LifelogPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final fade = animation.drive(CurveTween(curve: Curves.easeOut));
    final rise = animation.drive(
      Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    final under = secondaryAnimation.drive(
      Tween<double>(begin: 1, end: 0.94).chain(CurveTween(curve: Curves.easeOut)),
    );
    return FadeTransition(
      opacity: under,
      child: FadeTransition(
        opacity: fade,
        child: SlideTransition(position: rise, child: child),
      ),
    );
  }
}

/// Lets a mouse drag horizontal strips and pull-to-refresh on desktop.
class LifelogScrollBehavior extends MaterialScrollBehavior {
  const LifelogScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

/// App-specific tokens that are not part of Material's colour roles.
class LifelogPalette extends ThemeExtension<LifelogPalette> {
  const LifelogPalette({
    required this.card,
    required this.subtle,
    required this.border,
    required this.mutedText,
    required this.dimText,
    required this.journal,
    required this.tracker,
    required this.place,
    required this.music,
    required this.photo,
    required this.manual,
    required this.isDark,
  });

  final Color card;
  final Color subtle;
  final Color border;
  final Color mutedText;
  final Color dimText;

  // One colour per kind of record, used consistently on every screen.
  final Color journal;
  final Color tracker;
  final Color place;
  final Color music;
  final Color photo;
  final Color manual;

  final bool isDark;

  static LifelogPalette of(BuildContext context) =>
      Theme.of(context).extension<LifelogPalette>()!;

  @override
  LifelogPalette copyWith({
    Color? card,
    Color? subtle,
    Color? border,
    Color? mutedText,
    Color? dimText,
    Color? journal,
    Color? tracker,
    Color? place,
    Color? music,
    Color? photo,
    Color? manual,
    bool? isDark,
  }) {
    return LifelogPalette(
      card: card ?? this.card,
      subtle: subtle ?? this.subtle,
      border: border ?? this.border,
      mutedText: mutedText ?? this.mutedText,
      dimText: dimText ?? this.dimText,
      journal: journal ?? this.journal,
      tracker: tracker ?? this.tracker,
      place: place ?? this.place,
      music: music ?? this.music,
      photo: photo ?? this.photo,
      manual: manual ?? this.manual,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  LifelogPalette lerp(covariant LifelogPalette? other, double t) {
    if (other == null) return this;
    return LifelogPalette(
      card: Color.lerp(card, other.card, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      dimText: Color.lerp(dimText, other.dimText, t)!,
      journal: Color.lerp(journal, other.journal, t)!,
      tracker: Color.lerp(tracker, other.tracker, t)!,
      place: Color.lerp(place, other.place, t)!,
      music: Color.lerp(music, other.music, t)!,
      photo: Color.lerp(photo, other.photo, t)!,
      manual: Color.lerp(manual, other.manual, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
