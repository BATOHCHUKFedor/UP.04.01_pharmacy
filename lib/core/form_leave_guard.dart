class FormLeaveGuard {
  Future<bool> Function()? _confirm;

  void attach(Future<bool> Function() callback) => _confirm = callback;

  void detach(Future<bool> Function() callback) {
    if (identical(_confirm, callback)) _confirm = null;
  }

  Future<bool> confirm() => _confirm?.call() ?? Future<bool>.value(true);
}
