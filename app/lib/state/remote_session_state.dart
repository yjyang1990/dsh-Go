import 'dart:async';

import 'package:dsh_remote/dsh_remote.dart' show RemoteHostSession, RemoteTunnelCarrier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'read_list_identity.dart';

/// Observe the live tunnel, including replacements that keep the same client.
final liveRemoteSessionProvider = StreamProvider.autoDispose<RemoteHostSession?>((ref) {
  final carrier = ref.watch(readListLiveConnectionProvider)?.client.carrier;
  if (carrier is! RemoteTunnelCarrier) return Stream.value(null);
  final controller = StreamController<RemoteHostSession?>();
  void publish() {
    final session = carrier.session;
    controller.add(session?.isClosed == false ? session : null);
  }

  final sessions = carrier.sessions.listen((_) => publish());
  final states = carrier.states.listen((_) => publish());
  publish();
  ref.onDispose(() {
    unawaited(sessions.cancel());
    unawaited(states.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});
