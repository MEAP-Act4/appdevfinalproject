import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/design_tokens.dart';
import '../../common/motion_widgets.dart';
import '../../common/surface_card.dart';

/// Groups tiles into one card with hairline dividers, per DESIGN.md §3.
class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.children, this.accent});

  final List<Widget> children;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SurfaceCard(
      accent: accent,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (var i = 0; i < children.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: palette.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _TileShell extends StatelessWidget {
  const _TileShell({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.titleColor,
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? titleColor;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s3,
        vertical: Tokens.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: Tokens.s3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: titleColor ??
                            (enabled
                                ? palette.textPrimary
                                : palette.textSecondary),
                      ),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: Tokens.s2),
                trailing!,
              ],
            ],
          ),
          if (footer != null) ...<Widget>[
            const SizedBox(height: Tokens.s2),
            footer!,
          ],
        ],
      ),
    );

    if (onTap == null || !enabled) {
      return Opacity(opacity: enabled ? 1 : 0.5, child: body);
    }

    return InkWell(onTap: onTap, child: body);
  }
}

/// Boolean setting.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _TileShell(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      leading: icon == null
          ? null
          : Icon(icon, size: 20, color: palette.textSecondary),
      onTap: enabled ? () => onChanged(!value) : null,
      trailing: Switch.adaptive(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// Tile that opens a picker sheet and shows the current choice.
class SettingChoice<T> extends StatelessWidget {
  const SettingChoice({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.descriptionOf,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final String Function(T)? descriptionOf;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _TileShell(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      leading: icon == null
          ? null
          : Icon(icon, size: 20, color: palette.textSecondary),
      onTap: enabled ? () => _open(context) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SoftSwitcher(
            child: Text(
              labelOf(value),
              key: ValueKey<String>(labelOf(value)),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: palette.accentText),
            ),
          ),
          const SizedBox(width: Tokens.s1),
          Icon(
            Icons.unfold_more_rounded,
            size: 16,
            color: palette.textSecondary,
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final palette = AppPalette.of(context);
    final selected = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Tokens.s4,
                  0,
                  Tokens.s4,
                  Tokens.s2,
                ),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // Hand-rolled selection rows rather than RadioListTile: the
              // grouped-radio API has churned across Flutter versions and this
              // needs no group plumbing for a one-shot picker sheet.
              for (var i = 0; i < options.length; i++)
                FadeSlideIn(
                  index: i,
                  offset: 8,
                  child: ListTile(
                    onTap: () => Navigator.of(context).pop(options[i]),
                    leading: Icon(
                      options[i] == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: options[i] == value
                          ? palette.accentText
                          : palette.textSecondary,
                      size: 20,
                    ),
                    title: Text(labelOf(options[i])),
                    subtitle: descriptionOf == null
                        ? null
                        : Text(
                            descriptionOf!(options[i]),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: palette.textSecondary),
                          ),
                  ),
                ),
              const SizedBox(height: Tokens.s3),
            ],
          ),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }
}

/// Numeric setting with a slider and a live monospaced readout.
/// Commits on release so a device write does not fire on every pixel of drag.
class SettingSlider extends StatefulWidget {
  const SettingSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onCommitted,
    required this.format,
    this.divisions,
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onCommitted;
  final String Function(double) format;
  final IconData? icon;
  final bool enabled;

  @override
  State<SettingSlider> createState() => _SettingSliderState();
}

class _SettingSliderState extends State<SettingSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final current = _dragValue ?? widget.value;

    return _TileShell(
      title: widget.title,
      subtitle: widget.subtitle,
      enabled: widget.enabled,
      leading: widget.icon == null
          ? null
          : Icon(widget.icon, size: 20, color: palette.textSecondary),
      trailing: Text(
        widget.format(current),
        style: AppText.mono(
          size: 14,
          weight: FontWeight.w600,
          // The read-out is text; the slider track below stays graphical.
          color: palette.accentText,
        ),
      ),
      footer: Slider(
        value: current.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        onChanged: widget.enabled
            ? (v) => setState(() => _dragValue = v)
            : null,
        onChangeEnd: widget.enabled
            ? (v) {
                setState(() => _dragValue = null);
                widget.onCommitted(v);
              }
            : null,
      ),
    );
  }
}

/// Tappable action row.
class SettingAction extends StatelessWidget {
  const SettingAction({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final IconData? icon;
  final bool destructive;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final colour = destructive ? palette.alert : palette.textPrimary;
    return _TileShell(
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      titleColor: destructive ? palette.alert : null,
      leading: icon == null
          ? null
          : Icon(
              icon,
              size: 20,
              color: destructive ? palette.alert : palette.textSecondary,
            ),
      onTap: enabled ? onTap : null,
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded, size: 20, color: colour),
    );
  }
}

/// Read-only key/value row.
class SettingInfo extends StatelessWidget {
  const SettingInfo({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.valueColor,
  });

  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return _TileShell(
      title: title,
      subtitle: subtitle,
      leading: icon == null
          ? null
          : Icon(icon, size: 20, color: palette.textSecondary),
      trailing: Text(
        value,
        style: AppText.mono(
          size: 13,
          weight: FontWeight.w600,
          color: valueColor ?? palette.textSecondary,
        ),
      ),
    );
  }
}

/// Inline editable text row, used for sensor names.
class SettingTextField extends StatefulWidget {
  const SettingTextField({
    super.key,
    required this.title,
    required this.value,
    required this.onSubmitted,
    this.hint,
    this.icon,
    this.maxLength = 24,
  });

  final String title;
  final String value;
  final ValueChanged<String> onSubmitted;
  final String? hint;
  final IconData? icon;
  final int maxLength;

  @override
  State<SettingTextField> createState() => _SettingTextFieldState();
}

class _SettingTextFieldState extends State<SettingTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.onSubmitted(_controller.text);
    });
  }

  @override
  void didUpdateWidget(SettingTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.s3,
        vertical: Tokens.s2,
      ),
      child: Row(
        children: <Widget>[
          if (widget.icon != null) ...<Widget>[
            Icon(widget.icon, size: 20, color: palette.textSecondary),
            const SizedBox(width: Tokens.s3),
          ],
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              maxLength: widget.maxLength,
              textInputAction: TextInputAction.done,
              onSubmitted: widget.onSubmitted,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                labelText: widget.title,
                hintText: widget.hint,
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                  borderSide: BorderSide(color: palette.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
