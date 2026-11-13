import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/core/wire_guard_status.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

/// Shows what the WireGuard outbounds are doing and offers the one action that
/// repairs a switched network: dropping the transport the Core still holds.
class WireGuardCard extends ConsumerStatefulWidget {
  const WireGuardCard({super.key});

  @override
  ConsumerState<WireGuardCard> createState() => _WireGuardCardState();
}

class _WireGuardCardState extends ConsumerState<WireGuardCard>
    with WidgetsBindingObserver, ActivePollingMixin<WireGuardCard> {
  List<WireGuardStatus> _statuses = const [];
  var _reconnecting = false;

  @override
  Duration get pollInterval => const Duration(seconds: 3);

  @override
  Future<void> poll(PollGuard isCurrent) async {
    final statuses = await _read();
    if (!isCurrent() || !mounted) {
      return;
    }
    setState(() => _statuses = statuses);
  }

  Future<List<WireGuardStatus>> _read() async {
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      return const [];
    }
    try {
      return await ref.read(coreHandlerProvider).getWireGuardStatus();
    } catch (error) {
      commonPrint.log(
        'read wireguard status: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return const [];
    }
  }

  Future<void> _reconnect() async {
    if (_reconnecting) {
      return;
    }
    setState(() => _reconnecting = true);
    try {
      await ref.read(coreHandlerProvider).resetWireGuard(full: true);
    } catch (error) {
      commonPrint.log(
        'reset wireguard: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
    if (!mounted) {
      return;
    }
    setState(() => _reconnecting = false);
    await poll(() => mounted);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final detailStyle = DashboardText.label(context);
    final coreConnected =
        ref.watch(coreStatusProvider) == CoreStatus.connected;
    final statuses = _statuses;
    final primary = coreConnected && statuses.isNotEmpty
        ? statuses.first
        : null;
    return DashboardCard(
      semanticLabel: appLocalizations.wireGuard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.vpn,
            title: appLocalizations.wireGuard,
            trailing: [
              DashboardIconButton(
                glyph: AppGlyphs.sync,
                tooltip: appLocalizations.wireGuardReconnect,
                onPressed: primary == null || _reconnecting
                    ? null
                    : _reconnect,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!coreConnected)
            Text(appLocalizations.notRunning, style: detailStyle)
          else if (primary == null)
            Text(appLocalizations.wireGuardNoOutbound, style: detailStyle)
          else ...[
            Row(
              children: [
                Expanded(
                  child: DashboardFitText(
                    primary.name,
                    style: DashboardText.rowTitle(context),
                  ),
                ),
                const SizedBox(width: 8),
                _statusChip(context, primary),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              primary.endpoint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: detailStyle,
            ),
            const SizedBox(height: 6),
            Text(
              '${appLocalizations.wireGuardLastHandshake}: '
              '${_handshakeDesc(context, primary)}',
              style: detailStyle,
            ),
            if (primary.failStreak > 0) ...[
              const SizedBox(height: 6),
              Text(
                appLocalizations.wireGuardFailedHandshakes(primary.failStreak),
                style: detailStyle,
              ),
            ],
            const SizedBox(height: 12),
            DashboardBlock(
              radius: 16,
              padding: const EdgeInsets.symmetric(vertical: 10),
              onTap: _reconnecting ? null : _reconnect,
              semanticLabel: appLocalizations.wireGuardReconnect,
              child: Center(
                child: Text(
                  _reconnecting
                      ? appLocalizations.wireGuardReconnecting
                      : appLocalizations.wireGuardReconnect,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  DashboardChip _statusChip(BuildContext context, WireGuardStatus status) {
    final appLocalizations = context.appLocalizations;
    if (status.gaveUp) {
      return DashboardChip(
        label: appLocalizations.disconnected,
        tone: DashboardChipTone.warn,
        dot: true,
      );
    }
    if (!status.initialized) {
      return DashboardChip(
        label: appLocalizations.wireGuardIdle,
        tone: DashboardChipTone.idle,
        dot: true,
      );
    }
    if (status.failStreak > 0 || status.initError.isNotEmpty) {
      return DashboardChip(
        label: appLocalizations.connecting,
        tone: DashboardChipTone.warn,
        dot: true,
      );
    }
    return DashboardChip(
      label: appLocalizations.connected,
      tone: DashboardChipTone.ok,
      dot: true,
    );
  }

  String _handshakeDesc(BuildContext context, WireGuardStatus status) {
    final lastHandshake = status.lastHandshake;
    if (lastHandshake == null) {
      return context.appLocalizations.unknown;
    }
    return lastHandshake.getLastUpdateTimeDesc(context, compact: true);
  }
}
