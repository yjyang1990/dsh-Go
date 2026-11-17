import 'dart:async';

import 'package:dsh_app/ui/chat/composer.dart';
import 'package:dsh_app/ui/chat/input_prediction.dart';
import 'package:dsh_app/ui/chat/mention/mention_text_controller.dart';
import 'package:dsh_app/ui/chat/voice/voice_bridge.dart';
import 'package:dsh_app/ui/chat/voice/voice_controller.dart';
import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/composer_fakes.dart';
import 'support/harness.dart';

const _suggestion = RemoteInputPrediction(completionSeq: 12, text: '检查修改并运行测试');

class _PermissionBridge extends FakeVoiceBridge {
  final permissionReady = Completer<VoicePermission>();

  @override
  Future<VoicePermission> requestPermission() => permissionReady.future;
}

class _Rig {
  _Rig({FakeVoiceBridge? bridge}) : bridge = bridge ?? FakeVoiceBridge();

  final FakeVoiceBridge bridge;
  final editor = MentionTextController();
  late final voice = VoiceInputController(input: editor, bridge: bridge, client: () => null, observeLifecycle: false);
  var sent = 0;

  Future<void> pump(WidgetTester tester, Future<RemoteInputPrediction?> Function() read) async {
    usePhoneView(tester);
    addTearDown(editor.dispose);
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InputPrediction(scope: 'session', controller: editor, voice: voice, enabled: true, read: read),
              Composer(
                controller: editor,
                voice: voice,
                connected: true,
                running: false,
                onSend: () => sent++,
                onStop: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('dictation immediately blocks adoption, pauses through transcription, and resumes on empty final', (
    tester,
  ) async {
    final bridge = _PermissionBridge();
    final rig = _Rig(bridge: bridge);
    var reads = 0;
    await rig.pump(tester, () async {
      reads++;
      return _suggestion;
    });
    final adopt = tester.widget<TextButton>(find.widgetWithText(TextButton, '填入草稿')).onPressed!;
    final starting = rig.voice.start();
    expect(rig.voice.phase, VoicePhase.starting);
    // The rendered button can still receive a tap before the next frame.
    adopt();
    expect(rig.editor.text, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('填入草稿'), findsNothing);
    expect(reads, 1);
    bridge.permissionReady.complete(VoicePermission.granted);
    await starting;
    expect(rig.voice.phase, VoicePhase.listening);
    await rig.voice.stop();
    expect(rig.voice.phase, VoicePhase.transcribing);
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 1);
    bridge.emit(const VoiceFinal(''));
    await tester.pump();
    await tester.pump();
    expect(rig.voice.active, isFalse);
    expect(reads, 2);
    await tester.tap(find.text('填入草稿'));
    await tester.pump();
    expect(rig.editor.text, _suggestion.text);
    expect(rig.sent, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a pre-dictation read arriving after cancellation cannot replace the resumed suggestion', (tester) async {
    final rig = _Rig();
    final oldRead = Completer<RemoteInputPrediction?>();
    const fresh = RemoteInputPrediction(completionSeq: 13, text: '继续检查语音输入');
    var reads = 0;
    await rig.pump(tester, () => ++reads == 1 ? oldRead.future : Future.value(fresh));
    await rig.voice.start();
    await tester.pump(const Duration(seconds: 2));
    expect(rig.voice.phase, VoicePhase.listening);
    expect(reads, 1);
    await rig.voice.cancel();
    await tester.pump();
    expect(rig.editor.text, isEmpty);
    expect(find.text(fresh.text), findsOneWidget);
    oldRead.complete(_suggestion);
    await tester.pump();
    expect(find.text(_suggestion.text), findsNothing);
    expect(find.text(fresh.text), findsOneWidget);
    expect(reads, 2);
    expect(rig.sent, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('streaming words and empty partials stay owned by dictation; final speech remains a draft', (
    tester,
  ) async {
    final rig = _Rig();
    var reads = 0;
    await rig.pump(tester, () async {
      reads++;
      return _suggestion;
    });
    await rig.voice.start();
    rig.bridge.emit(const VoicePartial('帮我'));
    await tester.pump();
    expect(rig.editor.text, '帮我');
    expect(rig.editor.provisional, const TextRange(start: 0, end: 2));
    rig.bridge.emit(const VoicePartial(''));
    await tester.pump(const Duration(seconds: 2));
    expect(rig.editor.text, isEmpty);
    expect(find.text('填入草稿'), findsNothing);
    expect(reads, 1);
    rig.bridge.emit(const VoiceFinal('帮我检查日志'));
    await tester.pump();
    expect(rig.voice.active, isFalse);
    expect(rig.editor.text, '帮我检查日志');
    expect(rig.editor.provisional, TextRange.empty);
    expect(find.text('填入草稿'), findsNothing);
    expect(reads, 1);
    expect(rig.sent, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
