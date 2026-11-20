import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../remote/session_backup/backup_store.dart';
import 'hosts_state.dart';
import 'remote_session_state.dart';

final sessionBackupStoreProvider = FutureProvider<SessionBackupStore>((ref) async {
  final secrets = ref.watch(secretStoreProvider);
  final root = await getApplicationSupportDirectory();
  return SessionBackupStore.open(Directory('${root.path}/session-backups'), secrets);
});

final sessionBackupSessionProvider = liveRemoteSessionProvider;
