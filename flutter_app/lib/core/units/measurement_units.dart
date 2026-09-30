/// Unit handling for the app.
///
/// The firmware always talks in **litres per minute** and **litres**. Nothing in
/// the data layer or the database ever stores a converted value — conversion is a
/// presentation concern applied at the last moment. That keeps historical rows
/// comparable after the user changes the unit setting.
library;

/// Volumetric flow rate units.
enum FlowUnit {
  litresPerMinute('L/min', 1.0, 2),
  litresPerHour('L/h', 60.0, 1),
  litresPerSecond('L/s', 1 / 60, 3),
  usGallonsPerMinute('gal/min', 0.2641720524, 2),
  ukGallonsPerMinute('impgal/min', 0.2199692483, 2),
  cubicMetresPerHour('m³/h', 0.06, 3);

  const FlowUnit(this.symbol, this.fromLpm, this.decimals);

  /// Display symbol.
  final String symbol;

  /// Multiplier applied to a value in L/min.
  final double fromLpm;

  /// Sensible number of decimals for this unit's magnitude.
  final int decimals;

  double convert(double lpm) => lpm * fromLpm;

  double toLpm(double value) => value / fromLpm;

  String get label => switch (this) {
        FlowUnit.litresPerMinute => 'Litres per minute',
        FlowUnit.litresPerHour => 'Litres per hour',
        FlowUnit.litresPerSecond => 'Litres per second',
        FlowUnit.usGallonsPerMinute => 'US gallons per minute',
        FlowUnit.ukGallonsPerMinute => 'Imperial gallons per minute',
        FlowUnit.cubicMetresPerHour => 'Cubic metres per hour',
      };
}

/// Cumulative volume units.
enum VolumeUnit {
  litres('L', 1.0, 1),
  cubicMetres('m³', 0.001, 3),
  usGallons('gal', 0.2641720524, 1),
  ukGallons('impgal', 0.2199692483, 1);

  const VolumeUnit(this.symbol, this.fromLitres, this.decimals);

  final String symbol;
  final double fromLitres;
  final int decimals;

  double convert(double litres) => litres * fromLitres;

  double toLitres(double value) => value / fromLitres;

  String get label => switch (this) {
        VolumeUnit.litres => 'Litres',
        VolumeUnit.cubicMetres => 'Cubic metres',
        VolumeUnit.usGallons => 'US gallons',
        VolumeUnit.ukGallons => 'Imperial gallons',
      };

  /// The volume unit that naturally pairs with a flow unit, used when the user
  /// changes flow units and has not overridden volume.
  static VolumeUnit companionOf(FlowUnit flow) => switch (flow) {
        FlowUnit.litresPerMinute ||
        FlowUnit.litresPerHour ||
        FlowUnit.litresPerSecond =>
          VolumeUnit.litres,
        FlowUnit.usGallonsPerMinute => VolumeUnit.usGallons,
        FlowUnit.ukGallonsPerMinute => VolumeUnit.ukGallons,
        FlowUnit.cubicMetresPerHour => VolumeUnit.cubicMetres,
      };
}

/// Formats numbers for display with a fixed decimal count so the monospaced KPI
/// readouts do not change width as values move.
class UnitFormatter {
  const UnitFormatter({required this.flowUnit, required this.volumeUnit});

  final FlowUnit flowUnit;
  final VolumeUnit volumeUnit;

  /// Converts a L/min value and formats it, without the unit symbol.
  String flowValue(double lpm, {int? decimals}) {
    final converted = flowUnit.convert(lpm);
    return _fixed(converted, decimals ?? flowUnit.decimals);
  }

  /// Converts and formats with the unit symbol appended.
  String flow(double lpm, {int? decimals}) =>
      '${flowValue(lpm, decimals: decimals)} ${flowUnit.symbol}';

  String volumeValue(double litres, {int? decimals}) {
    final converted = volumeUnit.convert(litres);
    return _fixed(converted, decimals ?? volumeUnit.decimals);
  }

  String volume(double litres, {int? decimals}) =>
      '${volumeValue(litres, decimals: decimals)} ${volumeUnit.symbol}';

  static String _fixed(double value, int decimals) {
    if (value.isNaN || value.isInfinite) return '--';
    // Guard against "-0.00".
    final rounded = double.parse(value.toStringAsFixed(decimals));
    final safe = rounded == 0 ? 0.0 : rounded;
    return safe.toStringAsFixed(decimals);
  }

  /// Compact duration label, e.g. "2 h 14 m".
  static String duration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} m';
    if (d.inHours < 24) {
      final m = d.inMinutes.remainder(60);
      return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m m';
    }
    final h = d.inHours.remainder(24);
    return h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
  }
}
