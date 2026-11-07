import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/pixels.dart';
import 'common.dart';
import 'smooth_spinner.dart';

/// Signing in with Google, and how sync is doing.
class SyncSection extends StatefulWidget {
  const SyncSection({super.key, required this.sync});

  final SyncService sync;

  @override
  State<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends State<SyncSection> {
  Completer<void>? _cancel;
  String? _problem;

  Future<void> _signIn() async {
    final cancel = Completer<void>();
    setState(() {
      _cancel = cancel;
      _problem = null;
    });
    try {
      await widget.sync.turnOn(cancel: cancel.future);
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _cancel = null);
    }
  }

  static String _ago(DateTime t) {
    final minutes = DateTime.now().difference(t).inMinutes;
    if (minutes < 1) return 'just now';
    return minutes == 1 ? 'a minute ago' : minutes < 60 ? '$minutes minutes ago' : 'over an hour ago';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sync = widget.sync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final small = bodyStyle(p.inkMuted, size: 14);
        final problem = _problem ?? sync.error;
        if (sync.isOn) {
          final last = sync.lastSynced;
          return PixelColumn(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Signed in as ${sync.email}', style: bodyStyle(p.ink, size: 14)),
              const SizedBox(height: 4),
              PixelRow(
                children: [
                  if (sync.busy) ...[
                    SizedBox.square(dimension: 12, child: SmoothSpinner(color: p.accent)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      sync.busy
                          ? 'Syncing…'
                          : problem != null
                          ? 'Couldn’t sync: $problem'
                          : last == null
                          ? 'Waiting to sync.'
                          : 'Last synced ${_ago(last)}.',
                      style: !sync.busy && problem != null ? small.copyWith(color: p.missedInk) : small,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PixelRow(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PillButton(label: 'Sign out', onTap: sync.busy ? null : () => unawaited(sync.turnOff())),
                  const SizedBox(width: 8),
                  PillButton(label: 'Sync now', primary: true, onTap: sync.busy ? null : () => unawaited(sync.run())),
                ],
              ),
            ],
          );
        }
        final signingIn = _cancel != null;
        return PixelColumn(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              signingIn
                  ? 'Finish signing in in your browser, then come back here.'
                  : 'Keep your progress the same on all your devices: sign in with the same Google account on each. '
                        'Yue keeps it in a hidden folder in your Google Drive, and can’t see anything else there.',
              style: small,
            ),
            if (problem != null && !signingIn) ...[
              const SizedBox(height: 4),
              Text(problem, style: small.copyWith(color: p.missedInk)),
            ],
            const SizedBox(height: 8),
            PixelRow(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (signingIn)
                  PillButton(label: 'Cancel', onTap: () => _cancel?.complete())
                else
                  PillButton(label: 'Sign in with Google', primary: true, onTap: () => unawaited(_signIn())),
              ],
            ),
          ],
        );
      },
    );
  }
}
