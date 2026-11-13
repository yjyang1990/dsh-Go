import 'dart:async';

import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';

/// Host suggestions only enter the existing editor; its listener saves the draft.
class InputPrediction extends StatefulWidget {
  const InputPrediction({
    super.key,
    required this.scope,
    required this.controller,
    required this.read,
    required this.enabled,
  });

  final Object scope;
  final TextEditingController controller;
  final Future<RemoteInputPrediction?> Function() read;
  final bool enabled;

  @override
  State<InputPrediction> createState() => _InputPredictionState();
}

class _InputPredictionState extends State<InputPrediction> with WidgetsBindingObserver {
  Timer? _timer;
  int _epoch = 0;
  bool _active = false;
  bool _routeCurrent = true;
  bool _foreground = true;
  RemoteInputPrediction? _prediction;
  final _adopted = <Object, int>{};

  bool get _eligible =>
      widget.enabled &&
      _foreground &&
      _routeCurrent &&
      widget.controller.text.isEmpty &&
      widget.controller.value.composing.isCollapsed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    widget.controller.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _sync();
  }

  @override
  void didUpdateWidget(InputPrediction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    _sync(reset: oldWidget.scope != widget.scope || oldWidget.controller != widget.controller);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync({bool reset = false}) {
    final active = _eligible;
    if (!reset && active == _active) return;
    _timer?.cancel();
    final epoch = ++_epoch;
    _active = active;
    if (_prediction != null) setState(() => _prediction = null);
    if (active) unawaited(_poll(epoch));
  }

  Future<void> _poll(int epoch) async {
    try {
      final prediction = await widget.read();
      if (!mounted || epoch != _epoch || !_eligible) return;
      setState(() {
        _prediction = prediction != null && _adopted[widget.scope] != prediction.completionSeq ? prediction : null;
      });
    } on Exception {
      // A disconnected Host or missing plugin should not interrupt composing.
      if (mounted && epoch == _epoch) setState(() => _prediction = null);
    } finally {
      if (mounted && epoch == _epoch && _eligible) {
        _timer = Timer(const Duration(seconds: 1), () => unawaited(_poll(epoch)));
      }
    }
  }

  void _adopt() {
    final prediction = _prediction;
    if (prediction == null || !_eligible) return;
    _adopted[widget.scope] = prediction.completionSeq;
    widget.controller.value = TextEditingValue(
      text: prediction.text,
      selection: TextSelection.collapsed(offset: prediction.text.length),
    );
  }

  @override
  void dispose() {
    ++_epoch;
    _timer?.cancel();
    widget.controller.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prediction = _eligible ? _prediction : null;
    if (prediction == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(prediction.text, maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton(onPressed: _adopt, child: Text(context.l10n.chatAdoptPrediction)),
        ],
      ),
    );
  }
}
