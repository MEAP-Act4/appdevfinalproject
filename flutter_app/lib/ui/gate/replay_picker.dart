import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/ble/replay_transport.dart';
import '../../state/monitor_controller.dart';

/// A bottom sheet that lists `.csv` recordings found in the app's own storage
/// and starts a [ReplayTransport] at a chosen [ReplaySpeed].
///
/// Deliberately avoids a native file-picker plugin (one less fragile native
/// dependency in the cloud build): it scans the directories the app can write
/// to — the external files dir, where `Export CSV` lands, and the documents
/// dir. To replay your own data, export a CSV from the app (or copy one into
/// `Android/data/com.example.leakguard/files/`) and it appears here.
class ReplayPicker extends StatefulWidget {
  const ReplayPicker({super.key});

  static Future<void> show(BuildContext context) {
    final palette = AppPalette.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: palette.surface,
      builder: (_) => const ReplayPicker(),
    );
  }

  @override
  State<ReplayPicker> createState() => _ReplayPickerState();
}

class _ReplayPickerState extends State<ReplayPicker> {
  ReplaySpeed _speed = ReplaySpeed.fast;
  late Future<List<File>> _files;

  @override
  void initState() {
    super.initState();
    _files = _findCsvFiles();
  }

  Future<List<File>> _findCsvFiles() async {
    final dirs = <Directory?>[
      await getExternalStorageDirectory(),
      await getApplicationDocumentsDirectory(),
    ];
    final found = <String, File>{};
    for (final dir in dirs) {
      if (dir == null || !dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.csv')) {
          found[entity.path] = entity;
        }
      }
    }
    final list = found.values.toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return list;
  }

  Future<void> _start(File file) async {
    final monitor = context.read<MonitorController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final csv = await file.readAsString();
      await monitor.startReplay(
        csv,
        speed: _speed,
        label: file.uri.pathSegments.last,
      );
      if (mounted) navigator.pop();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read ${file.uri.pathSegments.last}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Tokens.s4, Tokens.s2, Tokens.s4, Tokens.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Replay recorded data', style: theme.textTheme.titleLarge),
            const SizedBox(height: Tokens.s1),
            Text(
              'Plays a real recording through the live leak-detection pipeline. '
              'The verdict is recomputed from the recorded flows, so a leak that '
              'develops over the recording is detected here just as it would be '
              'live — only faster.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: Tokens.s3),
            Text('Playback speed',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: palette.textSecondary)),
            const SizedBox(height: Tokens.s1),
            Wrap(
              spacing: Tokens.s2,
              children: <Widget>[
                for (final speed in ReplaySpeed.values)
                  ChoiceChip(
                    label: Text(speed.label),
                    selected: _speed == speed,
                    onSelected: (_) => setState(() => _speed = speed),
                  ),
              ],
            ),
            const SizedBox(height: Tokens.s3),
            Text('Recordings',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: palette.textSecondary)),
            const SizedBox(height: Tokens.s1),
            Flexible(
              child: FutureBuilder<List<File>>(
                future: _files,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(Tokens.s4),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final files = snapshot.data!;
                  if (files.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: Tokens.s3),
                      child: Text(
                        'No .csv recordings found. Export one from Settings → '
                        'Diagnostics (or copy a CSV into the app\'s files folder) '
                        'and it will appear here.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: palette.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: files.length,
                    separatorBuilder: (_, _) => Divider(
                        height: 1, color: palette.border),
                    itemBuilder: (context, index) {
                      final file = files[index];
                      final name = file.uri.pathSegments.last;
                      final sizeKb =
                          (file.statSync().size / 1024).toStringAsFixed(0);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.description_outlined,
                            color: palette.accentText),
                        title: Text(name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('$sizeKb KB',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: palette.textSecondary)),
                        trailing: const Icon(Icons.play_arrow_rounded),
                        onTap: () => _start(file),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
