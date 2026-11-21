import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/cupertino.dart';
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

  /// Horizontal page gutter on phones. Matches the iOS 16pt system margin.
  static const double page = 16;
}

/// Corner radii. Larger surfaces get larger radii; controls stay tighter.
class Radii {
  const Radii._();

  static const double sm = 8;
  static const double md = 10;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Durations and curves. Motion answers a touch or explains a change; it is
/// never decoration.
class Motion {
  const Motion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 480);

  /// Sheets and large layout changes.
  static const Duration sheet = Duration(milliseconds: 360);

  static const Curve out = Curves.easeOutCubic;
  static const Curve inOut = Curves.easeInOutCubic;

  /// Decelerating curve for things that arrive (sheets, headers). Settles
  /// without overshoot.
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Kept for existing call sites. Prefer [out]: overshoot reads as playful,
  /// not calm.
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

  /// Users who ask for more contrast get opaque surfaces instead of glass.
  bool get highContrast => MediaQuery.highContrastOf(this);
}

class AppTheme {
  const AppTheme._();

  // Brand seed. Everything else is hand-tuned below.
  static const seed = Color(0xFF2F5FE0);

  /// The mark keeps a serif initial; the interface itself uses the system
  /// sans (SF on Apple platforms, Roboto elsewhere) so text feels native.
  static const serifFamily = 'Georgia';
  static const serifFallback = <String>[
    'Georgia',
    'Noto Serif',
    'Cambria',
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

    // iOS system grouped backgrounds: near-black in dark, soft grey in light.
    // Cards stay opaque; translucency is reserved for the tab bar.
    final surface = dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final card = dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final subtle = dark ? const Color(0xFF2C2C2E) : const Color(0xFFE9E9EE);
    final border = dark ? const Color(0x29FFFFFF) : const Color(0x1A3C3C43);
    final ink = dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E);

    // One restrained accent. Everything else is neutral.
    final primary = dark ? const Color(0xFF7FA0FF) : const Color(0xFF2F5FE0);

    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xFF0F1530) : Colors.white,
          primaryContainer: primary.withValues(alpha: dark ? 0.18 : 0.10),
          onPrimaryContainer: primary,
          secondary: dark ? const Color(0xFFE3BC7A) : const Color(0xFF8F6420),
          tertiary: dark ? const Color(0xFF7CCBA4) : const Color(0xFF2B7A58),
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: ink.withValues(alpha: 0.78),
          surfaceContainerLowest: surface,
          surfaceContainerLow: card,
          surfaceContainer: card,
          surfaceContainerHigh: subtle,
          surfaceContainerHighest: subtle,
          outline: dark ? const Color(0xFF4A4E5A) : const Color(0xFFB9BBC4),
          outlineVariant: border,
          error: dark ? const Color(0xFFF29A94) : const Color(0xFFB8352C),
        );

    final palette = LifelogPalette(
      card: card,
      subtle: subtle,
      border: border,
      // Body-level secondary text. Kept readable against both card surfaces.
      mutedText: ink.withValues(alpha: 0.78),
      // Non-essential metadata only (timestamps, footnotes). Never the only
      // carrier of meaning, but still readable without relying on colour alone.
      dimText: ink.withValues(alpha: 0.66),
      glass: dark ? const Color(0xD91C1C1E) : const Color(0xD9FFFFFF),
      success: scheme.tertiary,
      warning: scheme.secondary,
      // One colour per kind of record, kept low in saturation so a mixed
      // timeline reads as a family, not a rainbow.
      journal: primary,
      tracker: scheme.tertiary,
      place: dark ? const Color(0xFF86BCD6) : const Color(0xFF3B7A99),
      music: dark ? const Color(0xFFBBA8E6) : const Color(0xFF7A62B5),
      photo: dark ? const Color(0xFFDDB27A) : const Color(0xFFA9702B),
      manual: dark ? const Color(0xFFA7ABB8) : const Color(0xFF6B6F7B),
      // High-contrast foreground for labels drawn over artwork/photographs.
      onPhoto: Colors.white,
      isDark: dark,
    );

    final text = _textTheme(scheme);

    RoundedRectangleBorder rounded(double r) =>
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

    return ThemeData(
      useMaterial3: true,
      platform: TargetPlatform.iOS,
      typography: Typography.material2021(platform: TargetPlatform.iOS),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      textTheme: text,
      extensions: <ThemeExtension<dynamic>>[palette],
      // iOS has no circular ink ripple; Pressable supplies the feedback.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
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
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: subtle,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: ink.withValues(alpha: 0.50)),
        labelStyle: TextStyle(color: ink.withValues(alpha: 0.66)),
        border: _inputBorder(Colors.transparent),
        enabledBorder: _inputBorder(Colors.transparent),
        disabledBorder: _inputBorder(Colors.transparent),
        focusedBorder: _inputBorder(primary.withValues(alpha: 0.8), width: 1.2),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: rounded(Radii.md),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          side: BorderSide(color: border),
          shape: rounded(Radii.md),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: rounded(Radii.xl),
        titleTextStyle: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: card,
        modalBarrierColor:
            Colors.black.withValues(alpha: dark ? 0.55 : 0.30),
        showDragHandle: true,
        dragHandleColor: ink.withValues(alpha: 0.18),
        dragHandleSize: const Size(38, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: rounded(Radii.md),
        textStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? const Color(0xFF2A2D36) : const Color(0xFF1E2026),
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
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: rounded(Radii.xl),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: card,
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
    final base = Typography.material2021(platform: TargetPlatform.iOS);
    final t = (scheme.brightness == Brightness.dark ? base.white : base.black)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    TextStyle display(TextStyle? s, double size, double ls, double h) {
      return (s ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: FontWeight.w600,
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
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: t.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: t.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, height: 1.45),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, height: 1.4),
      labelLarge: t.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: t.labelMedium?.copyWith(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: t.labelSmall?.copyWith(
        fontSize: 11.5,
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
    required this.glass,
    required this.success,
    required this.warning,
    required this.journal,
    required this.tracker,
    required this.place,
    required this.music,
    required this.photo,
    required this.manual,
    this.onPhoto = Colors.white,
    required this.isDark,
  });

  final Color card;
  final Color subtle;
  final Color border;
  final Color mutedText;
  final Color dimText;

  /// Fill for frosted bars. Only meaningful over a [BackdropFilter].
  final Color glass;
  final Color success;
  final Color warning;

  // One colour per kind of record, used consistently on every screen.
  final Color journal;
  final Color tracker;
  final Color place;
  final Color music;
  final Color photo;
  final Color manual;

  /// Foreground for text/icons drawn on top of image or artwork surfaces.
  final Color onPhoto;

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
    Color? glass,
    Color? success,
    Color? warning,
    Color? journal,
    Color? tracker,
    Color? place,
    Color? music,
    Color? photo,
    Color? manual,
    Color? onPhoto,
    bool? isDark,
  }) {
    return LifelogPalette(
      card: card ?? this.card,
      subtle: subtle ?? this.subtle,
      border: border ?? this.border,
      mutedText: mutedText ?? this.mutedText,
      dimText: dimText ?? this.dimText,
      glass: glass ?? this.glass,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      journal: journal ?? this.journal,
      tracker: tracker ?? this.tracker,
      place: place ?? this.place,
      music: music ?? this.music,
      photo: photo ?? this.photo,
      manual: manual ?? this.manual,
      onPhoto: onPhoto ?? this.onPhoto,
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
      glass: Color.lerp(glass, other.glass, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      journal: Color.lerp(journal, other.journal, t)!,
      tracker: Color.lerp(tracker, other.tracker, t)!,
      place: Color.lerp(place, other.place, t)!,
      music: Color.lerp(music, other.music, t)!,
      photo: Color.lerp(photo, other.photo, t)!,
      manual: Color.lerp(manual, other.manual, t)!,
      onPhoto: Color.lerp(onPhoto, other.onPhoto, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
