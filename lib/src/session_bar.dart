import 'package:flutter/material.dart';

import 'approval.dart';
import 'session_controller.dart';
import 'version.dart';

/// Always-on-top green bar shown for the whole session.
class SessionBar extends StatelessWidget {
  const SessionBar({super.key, required this.controller});
  final SessionController controller;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  Widget _pair(BuildContext context) {
    final n = controller.pairName!;
    return Scaffold(
      backgroundColor: Colors.red.shade800,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.link, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Allow controller "${n.length > 22 ? n.substring(0, 22) : n}"?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Code ${controller.pairFp}  (compare with the one it shows)',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => controller.answerPairing(false),
              child: const Text('Deny', style: TextStyle(color: Colors.white)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade900,
              ),
              onPressed: () => controller.answerPairing(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _approve(BuildContext context) {
    final left = controller.approvalEnds == null
        ? 0
        : controller.approvalEnds!
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, 99);
    return Scaffold(
      backgroundColor: Colors.deepOrange.shade800,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.help_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Allow: ${controller.approvalText}?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Why: ${controller.approvalReason}. No answer in ${left}s = Deny.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => controller.answerApproval(false),
              child: const Text('Deny', style: TextStyle(color: Colors.white)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.deepOrange.shade900,
              ),
              onPressed: () => controller.answerApproval(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (controller.pairName != null) return _pair(context);
    if (controller.approving) return _approve(context);
    final paused = controller.paused;
    return Scaffold(
      backgroundColor: paused
          ? Colors.blueGrey.shade700
          : Colors.green.shade800,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              paused ? Icons.pause_circle_filled : Icons.fiber_manual_record,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paused
                        ? 'ASSISTANT CONTROL PAUSED'
                        : 'ASSISTANT CONTROL ACTIVE  ${controller.expiresAt == null ? 'LIVE' : _fmt(controller.remaining)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    paused
                        ? 'Actions are refused until you press Resume'
                        : 'last: ${controller.lastAction}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
              ),
              onPressed: () => controller.setPaused(!paused),
              child: Text(paused ? 'RESUME' : 'PAUSE'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: paused
                    ? Colors.blueGrey.shade800
                    : Colors.green.shade800,
              ),
              onPressed: () => controller.stop('button'),
              child: const Text('STOP'),
            ),
          ],
        ),
      ),
    );
  }
}
