import 'package:dsh_client/dsh_client.dart';

import 'channel/rpc_client.dart';

/// A completed Host prediction. Reading it never starts generation.
class RemoteInputPrediction {
  const RemoteInputPrediction({required this.completionSeq, required this.text});

  final int completionSeq;
  final String text;
}

/// The Host's session preference and the global policy it is subject to.
class RemoteInputPredictionSetting {
  const RemoteInputPredictionSetting({required this.enabled, required this.forceEnabled, required this.globalEnabled});

  final bool enabled;
  final bool forceEnabled;
  final bool globalEnabled;

  bool get effectiveEnabled => globalEnabled && (forceEnabled || enabled);
}

class RemoteInputPredictionApi {
  const RemoteInputPredictionApi(this.rpc, {required this.capabilities, this.backend = 'harness'});

  static const capability = 'plugin.input-prediction.v1';
  static const settingCapability = 'plugin.input-prediction-setting.v1';
  final RemoteRpcClient rpc;
  final Iterable<String> capabilities;
  final String backend;

  bool get supported => backend == 'harness' && capabilities.contains(capability);
  bool get settingSupported => backend == 'harness' && capabilities.contains(settingCapability);

  /// A Host may support forwarding even when the desktop plugin is absent.
  Future<RemoteInputPredictionSetting?> readSetting(String sessionId) async {
    if (!settingSupported) return null;
    final json = await _requestSetting(sessionId);
    if (json == null) return null;
    final enabled = json['enabled'];
    final forceEnabled = json['forceEnabled'];
    final globalEnabled = json['globalEnabled'];
    if (enabled is! bool || forceEnabled is! bool || globalEnabled is! bool) {
      throw const DshProtocolException('Invalid input prediction setting');
    }
    return RemoteInputPredictionSetting(enabled: enabled, forceEnabled: forceEnabled, globalEnabled: globalEnabled);
  }

  Future<void> setSessionEnabled(String sessionId, bool enabled) async {
    if (!settingSupported) throw UnsupportedError('Input prediction settings are unavailable');
    final json = await _requestSetting(sessionId, enabled: enabled);
    if (json?['enabled'] is! bool || json?['forceEnabled'] is! bool) {
      throw const DshProtocolException('Invalid input prediction setting confirmation');
    }
  }

  Future<Map<Object?, Object?>?> _requestSetting(String sessionId, {bool? enabled}) async {
    final response = await rpc.call('plugin.route.call', {
      'route': 'api/dsh-input-prediction/session-setting',
      'body': {'sessionId': sessionId, 'enabled': ?enabled},
    });
    if (response is! Map || response['status'] is! int) {
      throw const DshProtocolException('Invalid input prediction setting response');
    }
    final status = response['status'] as int;
    if (status == 404 && enabled == null) return null;
    if (status != 200) throw DshHttpException(status, 'Input prediction setting request failed');
    final json = response['json'];
    if (json is! Map) throw const DshProtocolException('Invalid input prediction setting response');
    return json.cast<Object?, Object?>();
  }

  Future<RemoteInputPrediction?> read(String sessionId) async {
    if (!supported) return null;
    final response = await rpc.call('plugin.route.call', {
      'route': 'api/dsh-input-prediction',
      'body': {'sessionId': sessionId},
    });
    if (response is! Map || response['status'] is! int) {
      throw const DshProtocolException('Invalid input prediction response');
    }
    // The capability advertises forwarding, not installation of the plugin.
    if (response['status'] == 404) return null;
    if (response['status'] != 200) {
      throw DshHttpException(response['status'] as int, 'Input prediction read failed');
    }
    final json = response['json'];
    if (json is! Map) throw const DshProtocolException('Invalid input prediction state');
    if (json['status'] == 'none' || json['status'] == 'pending') return null;
    final seq = json['completionSeq'];
    final prediction = json['prediction'];
    if (json['status'] != 'ready' || seq is! int || seq < 0 || prediction is! String) {
      throw const DshProtocolException('Invalid ready input prediction');
    }
    if (prediction.trim().isEmpty) return null;
    return RemoteInputPrediction(completionSeq: seq, text: prediction);
  }
}
