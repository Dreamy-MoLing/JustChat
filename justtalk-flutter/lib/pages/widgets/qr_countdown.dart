import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/chat_state.dart';

/// QR 码 5 分钟倒计时指示器
class QrCountdown extends StatefulWidget {
  final DateTime createdAt;
  const QrCountdown({super.key, required this.createdAt});

  @override
  State<QrCountdown> createState() => _QrCountdownState();
}

class _QrCountdownState extends State<QrCountdown> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = PairingCode.expirySeconds -
        DateTime.now().difference(widget.createdAt).inSeconds;
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final newRemaining = PairingCode.expirySeconds -
            DateTime.now().difference(widget.createdAt).inSeconds;
        if (newRemaining <= 0) {
          timer.cancel();
        }
        setState(() { _remaining = newRemaining; });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _remaining <= 0;
    return Text(
      expired ? '已过期' : '${_remaining ~/ 60}:${(_remaining % 60).toString().padLeft(2, '0')}',
      style: TextStyle(
        fontSize: 12,
        color: expired ? Colors.red : Colors.grey,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
