import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// JTC1 应答码展示页面
///
/// 当用户扫描 JTC1 offer 后，自动生成 answer 并展示二维码。
/// 标题提示对方扫描此应答码。
class AnswerQrPage extends StatelessWidget {
  final String answerCode;
  final String peerDisplayName;

  const AnswerQrPage({
    super.key,
    required this.answerCode,
    required this.peerDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应答码'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('请让 $peerDisplayName 扫描此应答码',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('对方扫码后将自动连接',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: answerCode,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
