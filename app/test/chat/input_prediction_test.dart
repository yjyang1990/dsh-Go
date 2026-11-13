import 'dart:async';

import 'package:dsh_app/state/draft_store.dart';
import 'package:dsh_app/ui/chat/input_prediction.dart';
import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

const suggestion = RemoteInputPrediction(completionSeq: 12, text: '检查修改并运行测试');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('adopts through the editor listener into the existing draft store, once per completion', (tester) async {
    final editor = TextEditingController();
    final container = ProviderContainer();
    addTearDown(editor.dispose);
    addTearDown(container.dispose);
    final store = container.read(draftStoreProvider.notifier);
    editor.addListener(() => store.save('host/workspace/session', editor.text, const []));
    var reads = 0;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: InputPrediction(
            scope: ('host', 'harness', 'workspace', 'session'),
            controller: editor,
            enabled: true,
            read: () async {
              reads++;
              return suggestion;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(suggestion.text), findsOneWidget);
    expect(editor.text, isEmpty);
    expect(container.read(draftStoreProvider).drafts, isEmpty);
    await tester.tap(find.text('填入草稿'));
    await tester.pump();
    expect(editor.text, suggestion.text);
    expect(editor.selection.baseOffset, suggestion.text.length);
    expect(container.read(draftStoreProvider).drafts['host/workspace/session']?.text, suggestion.text);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 1, reason: 'Nonempty draft stops polling');
    expect((await SharedPreferences.getInstance()).getString(DraftStore.preferenceKey), contains(suggestion.text));
    editor.clear();
    await tester.pump();
    expect(find.text('填入草稿'), findsNothing);
    expect(reads, 2);
    await store.flush();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('typing during a pending read preserves the draft and ignores the late result', (tester) async {
    final editor = TextEditingController();
    addTearDown(editor.dispose);
    final pending = Completer<RemoteInputPrediction?>();
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: InputPrediction(scope: 'session', controller: editor, enabled: true, read: () => pending.future),
        ),
      ),
    );
    editor.text = '我自己的草稿';
    pending.complete(suggestion);
    await tester.pump();
    expect(editor.text, '我自己的草稿');
    expect(find.text('填入草稿'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scopeB in [
    ('host-B', 'harness', 'workspace-A', 'session-A'),
    ('host-A', 'codex', 'workspace-A', 'session-A'),
    ('host-A', 'harness', 'workspace-B', 'session-A'),
    ('host-A', 'harness', 'workspace-A', 'session-B'),
  ]) {
    testWidgets('scope $scopeB drops the previous late read', (tester) async {
      final editor = TextEditingController();
      addTearDown(editor.dispose);
      final oldRead = Completer<RemoteInputPrediction?>();
      Future<void> show(Object scope, Future<RemoteInputPrediction?> Function() read) async {
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: InputPrediction(scope: scope, controller: editor, enabled: true, read: read),
            ),
          ),
        );
      }

      await show(('host-A', 'harness', 'workspace-A', 'session-A'), () => oldRead.future);
      await show(scopeB, () async => null);
      oldRead.complete(suggestion);
      await tester.pump();
      expect(find.text('填入草稿'), findsNothing);
      expect(editor.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('busy or unsupported pauses reads and hides suggestions; resume reads again', (tester) async {
    final editor = TextEditingController();
    addTearDown(editor.dispose);
    var reads = 0;
    Future<void> show(bool enabled) => tester.pumpWidget(
      testApp(
        Scaffold(
          body: InputPrediction(
            scope: 'session',
            controller: editor,
            enabled: enabled,
            read: () async {
              reads++;
              return suggestion;
            },
          ),
        ),
      ),
    );
    await show(false);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 0);
    await show(true);
    await tester.pump();
    expect(find.text('填入草稿'), findsOneWidget);
    await show(false);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('填入草稿'), findsNothing);
    expect(reads, 1);
    await show(true);
    await tester.pump();
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('IME composition hides suggestion and leaves composing value intact', (tester) async {
    final editor = TextEditingController();
    addTearDown(editor.dispose);
    var reads = 0;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: InputPrediction(
            scope: 'session',
            controller: editor,
            enabled: true,
            read: () async {
              reads++;
              return suggestion;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    editor.value = const TextEditingValue(text: 'ni', composing: TextRange(start: 0, end: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('填入草稿'), findsNothing);
    expect(editor.value.composing, const TextRange(start: 0, end: 2));
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background and another route stop polling until visible again', (tester) async {
    final editor = TextEditingController();
    addTearDown(editor.dispose);
    var reads = 0;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: InputPrediction(
            scope: 'session',
            controller: editor,
            enabled: true,
            read: () async {
              reads++;
              return suggestion;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('填入草稿'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 2);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Another page')))));
    await tester.pumpAndSettle();
    final before = reads;
    await tester.pump(const Duration(seconds: 2));
    expect(reads, before);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(reads, greaterThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
    final disposedReads = reads;
    await tester.pump(const Duration(seconds: 2));
    expect(reads, disposedReads);
  });
}
