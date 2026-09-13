import 'dart:async';

typedef DismissalState = ({
  bool protectedFocus,
  bool leftDown,
  bool cancelDrag,
  bool fileOver,
});

class FocusDismissal {
  final Future<DismissalState> Function() readState;
  final Future<void> Function() dismiss;
  Timer? _timer;
  int _revision = 0;
  int _releaseTicks = 0;

  FocusDismissal({required this.readState, required this.dismiss});

  void cancel() {
    _revision++;
    _timer?.cancel();
    _timer = null;
    _releaseTicks = 0;
  }

  void request() {
    cancel();
    unawaited(_check(_revision));
  }

  Future<void> _check(int revision) async {
    final DismissalState state;
    try {
      state = await readState();
    } catch (_) {
      if (revision == _revision) cancel();
      return;
    }
    if (revision != _revision) return;
    if (state.protectedFocus) {
      cancel();
      return;
    }
    if (!state.cancelDrag && (state.leftDown || (state.fileOver && _releaseTicks++ < 5))) {
      if (state.leftDown) _releaseTicks = 0;
      _timer = Timer(const Duration(milliseconds: 50), () => _check(revision));
      return;
    }
    cancel();
    await dismiss();
  }
}
