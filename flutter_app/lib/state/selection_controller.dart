import 'package:flutter/foundation.dart';

import '../core/protocol/leak_protocol.dart';

/// The selected channel, shared across every presentation of the Sensors data.
///
/// This is the single owner of "which sensor is the user looking at" and it
/// deliberately lives *above* the Compact/Medium/Expanded presentation switch
/// (provided in `main.dart`, above `RootView` and its `LayoutBuilder`). The
/// Sensor_Carousel (Compact) and the Dashboard_View (Medium/Expanded) are
/// remounted when the Layout_Mode crosses a breakpoint; holding the selection
/// here — rather than as local widget state inside either presentation — is
/// what lets the active channel survive that remount (Requirement 4.3, 4.4).
///
/// Session-scoped: the selection is intentionally **not** persisted. It has no
/// dependency on `SettingsController` or `SharedPreferences`.
class SelectionController extends ChangeNotifier {
  SelectionController({int selectedChannel = 0})
    : _selectedChannel = selectedChannel.clamp(0, kSensorCount - 1);

  int _selectedChannel;

  /// The channel the user is currently viewing, always in `[0, kSensorCount)`.
  int get selectedChannel => _selectedChannel;

  /// Selects [channel], clamped to the valid sensor range `[0, kSensorCount)`.
  ///
  /// Out-of-range values are clamped rather than rejected (−1 → 0, 3 → 2 for
  /// three sensors). Listeners are notified only when the clamped result is an
  /// actual change from the current selection, so re-selecting the current
  /// channel is a no-op.
  void selectChannel(int channel) {
    final target = channel.clamp(0, kSensorCount - 1);
    if (target == _selectedChannel) return;
    _selectedChannel = target;
    notifyListeners();
  }
}
