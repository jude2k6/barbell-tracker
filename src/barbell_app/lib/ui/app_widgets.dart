import 'package:flutter/material.dart';

import '../workout/sensor_controller.dart';
import 'app_theme.dart';
import 'sensor_status_chip.dart';
import 'workout_flow.dart';

/// Small widgets shared by the screens, ported from Stance's design
/// system (`presentation/designsystem`) and common components.

/// Stance's `CircularIconButton`: a 44 dp circle at 5 % white. Without
/// [onPressed] it is only the visual (e.g. as a menu button's child).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton(
      {super.key, required this.icon, this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
          shape: BoxShape.circle, color: Color(0x0DFFFFFF)),
      child: Icon(icon, color: Colors.white),
    );
    if (onPressed == null) return circle;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
          customBorder: const CircleBorder(), onTap: onPressed, child: circle),
    );
  }
}

/// Stance's `stanceCard` modifier: white 4 % fill, 1 dp white 12 % stroke,
/// [radius] 20 dp by default.
BoxDecoration appCard({double radius = 20}) => BoxDecoration(
      color: AppColors.cardFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.cardStroke),
    );

/// Stance's `StanceButtonStyle`.
enum AppButtonStyle { primary, primaryDimmed, secondary, warning, idle }

/// Stance's `StanceButton` look as a [FilledButton] style: [radius]
/// corners (16 dp), a fixed [height] (42 dp), bodyLarge semibold text.
/// Disabled buttons get the idle look (white 6 %, gray text), as Stance's
/// do. Use it directly for buttons with custom children; [AppButton] is
/// the plain text button.
ButtonStyle appButtonStyle(
  BuildContext context, {
  AppButtonStyle style = AppButtonStyle.primary,
  double radius = 16,
  double height = 42,
}) {
  final (fill, text) = switch (style) {
    AppButtonStyle.primary => (AppColors.primary, Colors.white),
    AppButtonStyle.primaryDimmed =>
      (AppColors.primary.withValues(alpha: 0.2), Colors.white),
    AppButtonStyle.secondary => (Colors.transparent, AppColors.primary),
    AppButtonStyle.warning => (AppColors.error, Colors.white),
    AppButtonStyle.idle => (const Color(0x0FFFFFFF), AppColors.gray),
  };
  return FilledButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: text,
    disabledBackgroundColor: const Color(0x0FFFFFFF),
    disabledForegroundColor: AppColors.gray,
    minimumSize: Size.fromHeight(height),
    padding: const EdgeInsets.symmetric(horizontal: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    side: style == AppButtonStyle.secondary
        ? const BorderSide(color: AppColors.primary, width: 2)
        : null,
    textStyle: Theme.of(context)
        .textTheme
        .bodyLarge
        ?.copyWith(fontWeight: FontWeight.w600),
  );
}

/// Stance's `StanceButton`: a full-width text button in [appButtonStyle].
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.style = AppButtonStyle.primary,
    this.radius = 16,
    this.height = 42,
  });

  final String text;
  final VoidCallback? onPressed;
  final AppButtonStyle style;
  final double radius;
  final double height;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: appButtonStyle(context,
            style: style, radius: radius, height: height),
        onPressed: onPressed,
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center),
      );
}

/// Stance's `StanceSmallButton` look as a [FilledButton] style: a 32 dp
/// pill with 12/6 dp padding and bodyMedium bold text; primary is filled,
/// [secondary] is primary at 10 % with a 2 dp primary border.
ButtonStyle appSmallButtonStyle(BuildContext context, {bool secondary = false}) {
  final fill =
      secondary ? AppColors.primary.withValues(alpha: 0.1) : AppColors.primary;
  return FilledButton.styleFrom(
    backgroundColor: fill,
    foregroundColor: Colors.white,
    disabledBackgroundColor: fill.withValues(alpha: fill.a * 0.4),
    disabledForegroundColor: const Color(0x66FFFFFF),
    minimumSize: const Size(0, 32),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: const StadiumBorder(),
    side: secondary
        ? const BorderSide(color: AppColors.primary, width: 2)
        : null,
    textStyle: Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.w700),
  );
}

/// Stance's `StanceSmallButton`.
class AppSmallButton extends StatelessWidget {
  const AppSmallButton(this.text,
      {super.key, required this.onPressed, this.secondary = false});

  final String text;
  final VoidCallback? onPressed;
  final bool secondary;

  @override
  Widget build(BuildContext context) => FilledButton(
        style: appSmallButtonStyle(context, secondary: secondary),
        onPressed: onPressed,
        child: Text(text, textAlign: TextAlign.center),
      );
}

/// Stance's `ExtraSmallPillButton`: Purple2 20 % pill, Purple1 labelSmall
/// bold text and a 12 dp forward arrow.
class ExtraSmallPillButton extends StatelessWidget {
  const ExtraSmallPillButton(this.text, {super.key, required this.onPressed});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0x33782EFD),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(text,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.purple1, fontWeight: FontWeight.w700)),
              const SizedBox(width: 2),
              const Icon(Icons.arrow_forward, size: 12, color: AppColors.purple1),
            ]),
          ),
        ),
      );
}

/// Stance's `ExtraSmallButton` (GuideTipOverlay): a Purple2 20 % pill with
/// Purple1 11 sp bold text and an optional 14 dp icon.
class ExtraSmallButton extends StatelessWidget {
  const ExtraSmallButton(this.text,
      {super.key, required this.onPressed, this.icon, this.leadingIcon = false});

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool leadingIcon;

  @override
  Widget build(BuildContext context) {
    final glyph =
        icon == null ? null : Icon(icon, size: 14, color: AppColors.purple1);
    return Material(
      color: const Color(0x33782EFD),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leadingIcon && glyph != null) ...[glyph, const SizedBox(width: 2)],
            Text(text,
                style: const TextStyle(
                    fontSize: 11,
                    height: 16 / 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.purple1)),
            if (!leadingIcon && glyph != null) ...[const SizedBox(width: 2), glyph],
          ]),
        ),
      ),
    );
  }
}

/// Stance's `WorkoutTopBar`: a 44 dp row with the back button, then
/// [actions] and the device status on the right. The device status opens
/// the device page only when [deviceEnabled].
class WorkoutTopBar extends StatelessWidget {
  const WorkoutTopBar({
    super.key,
    required this.sensor,
    this.actions = const [],
    this.deviceEnabled = true,
    this.padding = EdgeInsets.zero,
  });

  final SensorController sensor;
  final List<Widget> actions;
  final bool deviceEnabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        padding: padding,
        child: Row(children: [
          CircleIconButton(
            key: const Key('workoutBack'),
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          for (final a in actions) ...[a, const SizedBox(width: 8)],
          SensorStatusChip(
              sensor: sensor,
              onPressed: deviceEnabled ? () => openDevice(context) : null),
        ]),
      );
}

/// Stance's `GuideHeaderButton`: a 32 dp pill with a 2 dp pink-to-primary
/// (70 %) gradient outline, an icon and 14 sp semibold text; half opacity
/// while disabled. Stance's icon is its `stance_ai` vector drawable; a
/// Material sparkle stands in.
class GuideHeaderButton extends StatelessWidget {
  const GuideHeaderButton({super.key, this.label = 'Guide', this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Tooltip(
          message: label,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 32,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                    colors: [Color(0xB3F415C3), Color(0xB3792EFF)]),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome, size: 20, color: AppColors.pink),
                  const SizedBox(width: 4),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// Stance's `StanceMenuPicker`: the current value in bodyMedium semibold
/// with a 16 dp chevron, in an 8 dp rounded box with a 1 dp gray 50 %
/// border; tapping opens a menu of [values]. [hint] shows while [value]
/// is null, if given.
class AppMenuPicker<T> extends StatelessWidget {
  const AppMenuPicker({
    super.key,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
    this.hint,
  });

  final T? value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600, color: Colors.white);
    final current = value;
    return PopupMenuButton<int>(
      tooltip: '',
      onSelected: (i) => onChanged(values[i]),
      itemBuilder: (_) => [
        for (final (i, v) in values.indexed)
          PopupMenuItem(value: i, child: Text(label(v))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0x80888888)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(
                current == null && hint != null ? hint! : label(current as T),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white),
        ]),
      ),
    );
  }
}

/// Stance's `StanceSegmentedTabs`: a 32 dp white 6 % track with 28 dp
/// tabs; the selected one is white 16 %, its label semibold white, the
/// others medium white 70 %. Full width unless [width] is given.
class AppSegmentedTabs<T> extends StatelessWidget {
  const AppSegmentedTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.keys = const {},
    this.width,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;

  /// Optional keys for the tab labels (for tests).
  final Map<T, Key> keys;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final body = Theme.of(context).textTheme.bodyMedium;
    return Container(
      width: width,
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        for (final v in values)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(v),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: v == selected ? const Color(0x29FFFFFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label(v),
                  key: keys[v],
                  style: body?.copyWith(
                    fontWeight: v == selected ? FontWeight.w600 : FontWeight.w500,
                    color: v == selected ? Colors.white : const Color(0xB3FFFFFF),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
