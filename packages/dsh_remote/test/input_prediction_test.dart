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

  Future<T> replyToSetting<T>(Future<T> result, Object response, {bool? enabled}) async {
    final request = await host.request.future;
    final payload = request.payload as Map;
    expect(payload['method'], 'plugin.route.call');
    expect(payload['params'], {
      'route': 'api/dsh-input-prediction/session-setting',
      'body': {'sessionId': 'session-A', 'enabled': ?enabled},
    });
    host.sendBytes(RemoteMessage('rpc.response', {'requestId': request.id, 'result': response}).encode());
    return result;
  }

  RemoteInputPredictionApi settingsApi() =>
      RemoteInputPredictionApi(host.rpc, capabilities: [RemoteInputPredictionApi.settingCapability]);

  test('reads the session preference separately from the host global policy', () async {
    final setting = await replyToSetting(settingsApi().readSetting('session-A'), {
      'status': 200,
      'json': {'enabled': true, 'forceEnabled': false, 'globalEnabled': false},
    });
    expect(setting?.enabled, isTrue);
    expect(setting?.forceEnabled, isFalse);
    expect(setting?.effectiveEnabled, isFalse);
  });

  test('forwards explicit false and accepts the existing desktop write reply', () async {
    await replyToSetting(settingsApi().setSessionEnabled('session-A', false), {
      'status': 200,
      'json': {'enabled': false, 'forceEnabled': false},
    }, enabled: false);
  });

  test('offers no setting on a result-only host or if the plugin is missing', () async {
    expect(await api().readSetting('session-A'), isNull);
    expect(host.request.isCompleted, isFalse);
    expect(await replyToSetting(settingsApi().readSetting('session-A'), {'status': 404}), isNull);
  });

  test('rejects a successful write response without a valid confirmation', () async {
    await expectLater(
      replyToSetting(settingsApi().setSessionEnabled('session-A', true), {
        'status': 200,
        'json': {'enabled': 'true', 'forceEnabled': false},
      }, enabled: true),
      throwsA(isA<DshProtocolException>()),
    );
  });

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
