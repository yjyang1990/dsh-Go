import 'package:dsh_remote/dsh_remote.dart' show RemoteInputPredictionApi, RemoteInputPredictionSetting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notify_state.dart' show appForegroundProvider;
import 'remote_session_state.dart';

final inputPredictionApiProvider = Provider<RemoteInputPredictionApi?>((ref) {
  final session = ref.watch(liveRemoteSessionProvider.select((value) => value.asData?.value));
  if (session == null || session.isClosed) return null;
  return RemoteInputPredictionApi(session.rpc, capabilities: session.capabilities);
});

// Including the API in the key isolates equal session IDs on different hosts.
typedef InputPredictionTarget = ({RemoteInputPredictionApi api, String sessionId});

final inputPredictionSettingProvider = AsyncNotifierProvider.autoDispose
    .family<InputPredictionSettingController, RemoteInputPredictionSetting?, InputPredictionTarget>(
      InputPredictionSettingController.new,
      retry: (_, _) => null,
    );

class InputPredictionSettingController extends AsyncNotifier<RemoteInputPredictionSetting?> {
  InputPredictionSettingController(this.target);

  final InputPredictionTarget target;
  bool _writing = false;

  @override
  Future<RemoteInputPredictionSetting?> build() async {
    final foreground = ref.watch(appForegroundProvider);
    if (!foreground || _writing) return null;
    return target.api.readSetting(target.sessionId);
  }

  void refresh() {
    if (!_writing && !state.isLoading) ref.invalidateSelf();
  }

  Future<void> setEnabled(bool enabled) async {
    final setting = state.value;
    if (state.isLoading ||
        _writing ||
        setting == null ||
        setting.forceEnabled ||
        setting.enabled == enabled ||
        !identical(ref.read(inputPredictionApiProvider), target.api)) {
      return;
    }
    // Keep the write serialized even if the user dismisses and reopens the sheet.
    final link = ref.keepAlive();
    _writing = true;
    state = const AsyncLoading();
    try {
      await target.api.setSessionEnabled(target.sessionId, enabled);
    } finally {
      _writing = false;
      // A failed/late response can still mean the Host committed the request.
      // Re-read once for the effective setting and the current global policy.
      if (ref.mounted && identical(ref.read(inputPredictionApiProvider), target.api)) ref.invalidateSelf();
      link.close();
    }
  }
}
