import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/drawer_view_state.dart';
import 'package:dsh_app/state/input_prediction_state.dart';
import 'package:dsh_app/state/notify_state.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/state/workspaces_state.dart';
import 'package:dsh_app/ui/shell/sessions_drawer.dart';
import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart';
import '../workspace/support.dart';

class _PredictionHost implements RemoteInputPredictionApi {
  @override
  bool settingSupported = true;
  bool forceEnabled = false;
  bool failWrite = false;
  final enabled = {'s1': false, 's2': true};
  final writes = <(String, bool)>[];

  @override
  Future<RemoteInputPredictionSetting?> readSetting(String sessionId) async =>
      RemoteInputPredictionSetting(enabled: enabled[sessionId]!, forceEnabled: forceEnabled, globalEnabled: true);

  @override
  Future<void> setSessionEnabled(String sessionId, bool value) async {
    if (failWrite) throw const DshHttpException(503, 'Test host unavailable');
    writes.add((sessionId, value));
    enabled[sessionId] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('session menu writes the host preference and reloads desktop changes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    usePhoneView(tester);
    final host = FakeWorkspaceHost()
      ..seedSession('s1', 'First', DateTime.now())
      ..seedSession('s2', 'Second', DateTime.now());
    final prediction = _PredictionHost();
    final connection = workspaceHost(host);
    addTearDown(connection.client.close);
    final ui = ChatHarness(session: 's1');
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SessionsDrawer(onClose: () {}, onOpen: (_) {}),
        ),
        overrides: [
          for (final o in ui.overrides)
            if (o.origin != activeConnectionProvider && o.origin != sessionsProvider) o,
          activeConnectionProvider.overrideWithValue(AsyncData(connection)),
          workspacePrefsProvider.overrideWith(() => FixedWorkspacePrefs(const WorkspacePrefs(loaded: true))),
          inputPredictionApiProvider.overrideWithValue(prediction),
        ],
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(SessionsDrawer)));
    for (var i = 0; i < 50 && container.read(drawerScopeProvider)?.readOnly != false; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(container.read(drawerScopeProvider)?.readOnly, isFalse);
    final shared = inputPredictionSettingProvider((api: prediction, sessionId: 's1'));
    // Represent the chat consumer, which stays mounted after the sheet closes.
    final subscription = container.listen(shared, (_, _) {});
    addTearDown(subscription.close);
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(SwitchListTile, '输入预测');

    await tester.longPress(find.widgetWithText(SessionTile, 'First'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    prediction.failWrite = true;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('输入预测设置未确认'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(prediction.writes, isEmpty);
    prediction.failWrite = false;
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(prediction.writes, [('s1', true)]);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(container.read(shared).value?.effectiveEnabled, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    prediction.enabled['s1'] = false;
    await tester.longPress(find.widgetWithText(SessionTile, 'First'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final foreground = container.read(appForegroundProvider.notifier);
    foreground.set(false);
    await tester.pumpAndSettle();
    prediction.enabled['s1'] = true;
    foreground.set(true);
    await tester.pumpAndSettle();
    expect(container.read(shared).value?.effectiveEnabled, isTrue);
    foreground.set(false);
    await tester.pumpAndSettle();
    prediction.enabled['s1'] = false;
    foreground.set(true);
    await tester.pumpAndSettle();
    expect(container.read(shared).value?.effectiveEnabled, isFalse);

    await tester.longPress(find.widgetWithText(SessionTile, 'Second'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(prediction.writes, [('s1', true)]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    prediction.forceEnabled = true;
    await tester.longPress(find.widgetWithText(SessionTile, 'First'));
    await tester.pumpAndSettle();
    expect(tile, findsNothing);
    expect(container.read(shared).value?.forceEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
