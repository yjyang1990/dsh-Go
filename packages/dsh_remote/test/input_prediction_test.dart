import 'package:dsh_remote/dsh_remote.dart';
import 'package:test/test.dart';

import 'support/rpc_event_host.dart';

void main() {
  late EventHost host;
  setUp(() async {
    host = EventHost();
    await host.start();
  });
  tearDown(() => host.close());

  RemoteInputPredictionApi api({String backend = 'harness', bool supported = true}) => RemoteInputPredictionApi(
    host.rpc,
    backend: backend,
    capabilities: supported ? [RemoteInputPredictionApi.capability] : [],
  );

  Future<RemoteInputPrediction?> readReply(Object response) async {
    final result = api().read('session-A');
    final request = await host.request.future;
    final payload = request.payload as Map;
    expect(payload['method'], 'plugin.route.call');
    expect(payload['params'], {
      'route': 'api/dsh-input-prediction',
      'body': {'sessionId': 'session-A'},
    });
    host.sendBytes(RemoteMessage('rpc.response', {'requestId': request.id, 'result': response}).encode());
    return result;
  }

  test('reads ready prediction using existing encrypted RPC channel', () async {
    final prediction = await readReply({
      'status': 200,
      'json': {'status': 'ready', 'completionSeq': 42, 'prediction': 'Review the changes'},
    });
    expect(prediction?.completionSeq, 42);
    expect(prediction?.text, 'Review the changes');
  });

  for (final backend in ['codex', 'acp']) {
    test('$backend never calls prediction RPC', () async {
      expect(await api(backend: backend).read('session-A'), isNull);
      expect(host.request.isCompleted, isFalse);
    });
  }

  test('older Host without capability never receives prediction RPC', () async {
    expect(await api(supported: false).read('session-A'), isNull);
    expect(host.request.isCompleted, isFalse);
  });

  for (final state in ['none', 'pending']) {
    test('$state has no suggestion', () async {
      expect(
        await readReply({
          'status': 200,
          'json': {'status': state},
        }),
        isNull,
      );
    });
  }

  test('uninstalled plugin has no suggestion', () async {
    expect(
      await readReply({
        'status': 404,
        'json': {'error': 'not found'},
      }),
      isNull,
    );
  });

  test('ready but declined prediction has no suggestion', () async {
    expect(
      await readReply({
        'status': 200,
        'json': {'status': 'ready', 'completionSeq': 42, 'prediction': '', 'reason': 'model_declined'},
      }),
      isNull,
    );
  });

  test('malformed ready state is rejected at the boundary', () async {
    await expectLater(
      readReply({
        'status': 200,
        'json': {'status': 'ready', 'completionSeq': '42', 'prediction': 'Review'},
      }),
      throwsA(isA<DshProtocolException>()),
    );
  });
}
