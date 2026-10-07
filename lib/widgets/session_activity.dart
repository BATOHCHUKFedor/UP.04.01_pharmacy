import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/auth_notifier.dart';

class SessionActivity extends StatefulWidget {
  final Widget child;
  const SessionActivity({super.key, required this.child});
  @override
  State<SessionActivity> createState() => _SessionActivityState();
}

class _SessionActivityState extends State<SessionActivity>
    with WidgetsBindingObserver {
  late AuthNotifier _auth;
  bool _keyboard(KeyEvent event) {
    _auth.touch();
    return false;
  }

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthNotifier>();
    HardwareKeyboard.instance.addHandler(_keyboard);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _auth.checkTimeout();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_keyboard);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _auth.touch(),
      onPointerHover: (_) => _auth.touch(),
      onPointerMove: (_) => _auth.touch(),
      onPointerSignal: (_) => _auth.touch(),
      child: widget.child,
    );
  }
}
