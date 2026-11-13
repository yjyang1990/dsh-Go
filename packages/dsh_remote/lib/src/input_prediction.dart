import 'package:dsh_client/dsh_client.dart';

import 'channel/rpc_client.dart';

/// A completed Host prediction. Reading it never starts generation.
class RemoteInputPrediction {
  const RemoteInputPrediction({required this.completionSeq, required this.text});

  final int completionSeq;
  final String text;
}

class RemoteInputPredictionApi {
  const RemoteInputPredictionApi(this.rpc, {required this.capabilities, this.backend = 'harness'});

  static const capability = 'plugin.input-prediction.v1';
  final RemoteRpcClient rpc;
  final Iterable<String> capabilities;
  final String backend;

  bool get supported => backend == 'harness' && capabilities.contains(capability);

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
