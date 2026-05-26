import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../main.dart';
import '../models/chat_state.dart';
import '../models/notification_state.dart';
import '../models/pairing_code.dart';
import 'chat_page.dart';
import 'info_page.dart';
import 'notifications_page.dart';
import 'qr_scanner_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _peerIdController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _peerIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _addContact() {
    final peerId = _peerIdController.text.trim();
    final name = _nameController.text.trim();
    if (peerId.isEmpty || name.isEmpty) return;
    context
        .read<ChatState>()
        .addContact(Contact(peerId: peerId, displayName: name));
    _peerIdController.clear();
    _nameController.clear();
    Navigator.pop(context);
  }

  void _showAddContactDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('添加联系人', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 20),
            TextField(
              controller: _peerIdController,
              decoration: const InputDecoration(
                hintText: '对方的 Peer ID',
                prefixIcon: Icon(Icons.fingerprint, color: JustChatApp.teal),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '显示名称',
                prefixIcon: Icon(Icons.person_outline, color: JustChatApp.teal),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _addContact,
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // QR code display (my QR code → others scan me)
  // ══════════════════════════════════════════════════════════════════════

  void _showMyQrCode() async {
    final state = context.read<ChatState>();

    // 惰性预连接：信令未连时先连接再展示 QR
    if (!state.signalingConnected) {
      // 弹 loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        await state.connectToSignaling().timeout(
          const Duration(seconds: 3),
        );
      } on TimeoutException {
        if (mounted) {
          Navigator.pop(context); // 关 loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('信令服务器连接超时，请检查网络后重试')),
          );
        }
        return;
      } catch (_) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('信令服务器连接失败')),
          );
        }
        return;
      }
      if (!state.signalingConnected) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('信令服务器连接失败')),
          );
        }
        return;
      }
      if (mounted) Navigator.pop(context); // 关 loading
    }

    final pairingCode = await state.generatePairingCode();
    if (!mounted) return;
    final qrData = pairingCode.encode();
    String? code = qrData;
    bool paired = false;

    // ── 设置配对回调：被扫码方感知有人扫码 ──
    state.onPairedFromQr = (peerId, displayName) {
      if (paired) return;
      paired = true;
      Navigator.pop(context); // 关闭 QR 弹窗
      // 提示用户
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$displayName 正在连接...'),
          duration: const Duration(seconds: 2),
        ),
      );
      // 导航到聊天页
      final width = MediaQuery.of(context).size.width;
      if (width < 600) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ChatPage()));
      }
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, dialogSetState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            title: Row(
              children: [
                const Text('我的二维码'),
                const Spacer(),
                // ── 5 分钟倒计时 ──
                _QrCountdown(createdAt: pairingCode.createdAt),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('让对方扫码连接我', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Card(
                    color: JustChatApp.cream.withAlpha(80),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person, size: 16, color: JustChatApp.teal.withAlpha(150)),
                          const SizedBox(width: 6),
                          Text(
                            '扫码后将以「${state.displayName}」身份连接',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        data: code,
                        version: QrVersions.auto,
                        size: 200,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: JustChatApp.teal,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: JustChatApp.teal,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('连接码已复制')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('复制'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Share.share(code),
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('分享'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Color(0xFF22C55E)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '扫码立即添加好友。双方连接信令服务器后自动完成 P2P 连接。',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  state.onPairedFromQr = null;
                  Navigator.pop(ctx);
                },
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // QR scanner (scan someone else's QR code)
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _openScanner() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (result != null && mounted) {
      final state = context.read<ChatState>();
      try {
        await state.handleConnectionCode(result);
        if (mounted && state.pendingAnswerCode != null) {
          _showAnswerQrCode(state.pendingAnswerCode!);
        } else if (mounted && result.startsWith('JTC2:')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('好友已添加，正在连接...')),
          );
          if (mounted && state.activeContactId.isNotEmpty) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChatPage()));
          }
        }
      } on PairingCodeExpiredException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString()), backgroundColor: Colors.orange),
          );
        }
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Show answer QR code (after scanning an offer)
  // ══════════════════════════════════════════════════════════════════════

  void _showAnswerQrCode(String answerCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text('已连接！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 64),
            const SizedBox(height: 12),
            const Text('连接成功，可以开始聊天了！', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            const Text('让对方扫描此应答码以完成连接：',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: QrImageView(
                  data: answerCode,
                  version: QrVersions.auto,
                  size: 180,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: JustChatApp.teal,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: JustChatApp.teal,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: answerCode));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('应答码已复制')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制应答码'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Share.share(answerCode),
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('分享'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ChatState>().clearPendingAnswer();
            },
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Share connection code via system share
  // ══════════════════════════════════════════════════════════════════════

  Future<void> _shareConnectionCode() async {
    final state = context.read<ChatState>();
    try {
      final code = (await state.generatePairingCode()).encode();
      if (!mounted) return;
      await Share.share(code);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成连接码失败: $e')),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Paste connection code / answer code (backup)
  // ══════════════════════════════════════════════════════════════════════

  void _showPasteCodeDialog() {
    final codeController = TextEditingController();
    bool loading = false;
    String? error;
    String? answerCode;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            title: const Text('粘贴连接码'),
            content: SizedBox(
              width: double.maxFinite,
              child: answerCode != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 48),
                        const SizedBox(height: 12),
                        const Text('连接已建立！'),
                        const SizedBox(height: 8),
                        const Text(
                          '将应答码发送给对方以完成连接：',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(
                              answerCode!,
                              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                              maxLines: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: answerCode!));
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('应答码已复制')),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('复制'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => Share.share(answerCode!),
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('分享'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('粘贴对方发来的连接码或应答码：'),
                        const SizedBox(height: 12),
                        TextField(
                          controller: codeController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'JTC1:...',
                            contentPadding: EdgeInsets.all(12),
                          ),
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                        if (loading) ...[
                          const SizedBox(height: 12),
                          const CircularProgressIndicator(),
                        ],
                      ],
                    ),
            ),
            actions: [
              if (answerCode != null)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('完成'),
                )
              else ...[
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: loading ? null : () async {
                    final code = codeController.text.trim();
                    if (code.isEmpty) return;
                    setState(() { loading = true; error = null; });
                    try {
                      final state = context.read<ChatState>();

                      // JTC2: short pairing code — immediate connect.
                      if (code.startsWith('JTC2:')) {
                        await state.handleConnectionCode(code);
                        if (ctx.mounted) {
                          setState(() {
                            loading = false;
                            answerCode = '[已连接]';
                          });
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('好友已添加，正在连接...')),
                          );
                          Future.delayed(const Duration(milliseconds: 800), () {
                            if (ctx.mounted) Navigator.pop(ctx);
                          });
                        }
                        return;
                      }

                      // JTC1: legacy flow.
                      await state.handleConnectionCode(code);
                      if (ctx.mounted) {
                        final pending = state.pendingAnswerCode;
                        setState(() {
                          answerCode = pending;
                          loading = false;
                        });
                        if (pending == null && ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                      }
                    } on PairingCodeExpiredException catch (e) {
                      if (ctx.mounted) setState(() { error = e.toString(); loading = false; });
                    } catch (e) {
                      if (ctx.mounted) setState(() { error = '无效的连接码: $e'; loading = false; });
                    }
                  },
                  child: const Text('连接'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Drawer
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildDrawer(BuildContext context) {
    final state = context.watch<ChatState>();
    final mq = MediaQuery.of(context);

    return Drawer(
      width: mq.size.width * 0.78,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
                top: mq.padding.top, left: 20, right: 20, bottom: 20),
            decoration: const BoxDecoration(color: JustChatApp.teal),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(height: mq.padding.top > 0 ? 0 : 12),
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: const Icon(Icons.chat_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 12),
                const Text('JustChat',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(state.displayName,
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _sectionHeader('信息'),
                ListTile(
                  leading: const Icon(Icons.person, color: JustChatApp.teal),
                  title: Text(state.displayName, style: const TextStyle(fontSize: 14)),
                  subtitle: const Text('点击设置可修改昵称', style: TextStyle(fontSize: 11)),
                ),
                if (state.lastError != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      state.lastError!,
                      style: const TextStyle(color: Colors.red, fontSize: 11),
                    ),
                  ),
                ],
                const Divider(),
                _sectionHeader('设置'),
                ListTile(
                  leading: const Icon(Icons.settings_rounded, color: JustChatApp.teal),
                  title: const Text('偏好设置', style: TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsPage()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded, color: JustChatApp.teal),
                  title: const Text('使用教程', style: TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const InfoPage()));
                  },
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.code_rounded, color: JustChatApp.teal),
                  title: Text('关于 JustChat', style: TextStyle(fontSize: 14)),
                  subtitle: Text('v0.1.0 · P2P 聊天', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title,
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: JustChatApp.teal, letterSpacing: 1.5)),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('JustChat'),
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              actions: [
                Consumer<NotificationState>(
                  builder: (_, ns, __) => Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationsPage())),
                      ),
                      if (ns.unreadCount > 0)
                        Positioned(
                          right: 8, top: 8,
                          child: Container(
                            width: 18, height: 18,
                            decoration: const BoxDecoration(
                                color: Colors.red, shape: BoxShape.circle),
                            child: Center(
                              child: Text('${ns.unreadCount}',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
      drawer: isDesktop ? null : _buildDrawer(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600) {
            return _buildDesktopLayout(context);
          }
          return _buildMobileLayout(context);
        },
      ),
      floatingActionButton: isDesktop
          ? null
          : FloatingActionButton.extended(
              onPressed: _showConnectionMenu,
              icon: const Icon(Icons.add_rounded),
              label: const Text('连接'),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // Responsive layouts
  // ══════════════════════════════════════════════════════════════════════

  Widget _buildDesktopLayout(BuildContext context) {
    return Consumer<ChatState>(
      builder: (context, state, _) {
        return Row(
          children: [
            SizedBox(
              width: 300,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('联系人'),
                  leading: PopupMenuButton<String>(
                    icon: const Icon(Icons.menu_rounded),
                    onSelected: (v) {
                      switch (v) {
                        case 'settings':
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SettingsPage()));
                          break;
                        case 'info':
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const InfoPage()));
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'settings', child: Text('设置')),
                      const PopupMenuItem(value: 'info', child: Text('使用教程')),
                    ],
                  ),
                  actions: [
                    Consumer<NotificationState>(
                      builder: (_, ns, __) => Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined),
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => const NotificationsPage())),
                          ),
                          if (ns.unreadCount > 0)
                            Positioned(
                              right: 8, top: 8,
                              child: Container(
                                width: 18, height: 18,
                                decoration: const BoxDecoration(
                                    color: Colors.red, shape: BoxShape.circle),
                                child: Center(
                                  child: Text('${ns.unreadCount}',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 10)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                body: _buildContactList(context, state),
                floatingActionButton: FloatingActionButton(
                  onPressed: _showConnectionMenu,
                  child: const Icon(Icons.add_rounded),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: state.activeContactId.isNotEmpty
                  ? ChatPage(embedded: true, key: ValueKey(state.activeContactId))
                  : const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_rounded,
                              size: 64, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('选择一个联系人开始聊天',
                              style: TextStyle(color: Colors.grey, fontSize: 15)),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Consumer<ChatState>(
      builder: (context, state, _) {
        if (state.contacts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 80, color: JustChatApp.teal.withAlpha(80)),
                const SizedBox(height: 16),
                Text('还没有联系人',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: JustChatApp.teal.withAlpha(150))),
                const SizedBox(height: 8),
                Text('点击右下角 + 连接第一个朋友',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey)),
              ],
            ),
          );
        }
        return _buildContactList(context, state);
      },
    );
  }

  Widget _buildContactList(BuildContext context, ChatState state) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: state.contacts.length,
      itemBuilder: (context, index) {
        final contact = state.contacts[index];
        final msgs = state.getMessages(contact.peerId);
        return Dismissible(
          key: Key(contact.peerId),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除联系人'),
              content: Text('确定删除「${contact.displayName}」吗？聊天记录也会被清除。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    state.removeContact(contact.peerId);
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.zero,
            ),
            child: const Icon(Icons.delete_rounded, color: Colors.white),
          ),
          child: _ContactCard(
            contact: contact,
            lastMessage: msgs.isNotEmpty ? msgs.last.content : null,
            connected: state.isPeerConnected(contact.peerId),
            onTap: () {
              state.setActiveContact(contact.peerId);
              final width = MediaQuery.of(context).size.width;
              if (width >= 600) {
                // 桌面模式：直接切换右侧面板，无需导航
                return;
              }
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ChatPage()));
            },
          ),
        );
      },
    );
  }

  void _showConnectionMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      builder: (ctx) {
        final bottomPad = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(top: 16, bottom: bottomPad + 8),
          child: ListView(
            shrinkWrap: true,
            primary: false,
            padding: EdgeInsets.zero,
            children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(100),
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('连接方式',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: JustChatApp.teal.withAlpha(20),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.camera_alt_rounded, color: JustChatApp.teal),
              ),
              title: const Text('扫码连接'),
              subtitle: const Text('扫描对方的二维码', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _openScanner();
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: JustChatApp.teal.withAlpha(20),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.qr_code_rounded, color: JustChatApp.teal),
              ),
              title: const Text('我的二维码'),
              subtitle: const Text('展示二维码让对方扫我', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _showMyQrCode();
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: JustChatApp.teal.withAlpha(20),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.share_rounded, color: JustChatApp.teal),
              ),
              title: const Text('分享连接码'),
              subtitle: const Text('通过微信/QQ发送给对方', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _shareConnectionCode();
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: JustChatApp.teal.withAlpha(20),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.paste_rounded, color: JustChatApp.teal),
              ),
              title: const Text('粘贴连接码'),
              subtitle: const Text('手动粘贴对方发来的连接码/应答码', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _showPasteCodeDialog();
              },
            ),
            const Divider(indent: 16, endIndent: 16),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: JustChatApp.creamDark.withAlpha(100),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.person_add_rounded, color: JustChatApp.teal),
              ),
              title: const Text('添加联系人'),
              subtitle: const Text('手动输入 Peer ID', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _showAddContactDialog();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
      },
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;
  final String? lastMessage;
  final bool connected;
  final VoidCallback onTap;

  const _ContactCard({
    required this.contact,
    this.lastMessage,
    this.connected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [JustChatApp.teal, JustChatApp.tealLight]),
                  borderRadius: BorderRadius.zero,
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(contact.initials,
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                    ),
                    if (contact.online || connected)
                      Positioned(
                        right: 2, bottom: 2,
                        child: Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.displayName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600)),
                    if (lastMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(lastMessage!, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: JustChatApp.teal.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }
}

/// QR 码 5 分钟倒计时指示器
class _QrCountdown extends StatefulWidget {
  final DateTime createdAt;
  const _QrCountdown({required this.createdAt});

  @override
  State<_QrCountdown> createState() => _QrCountdownState();
}

class _QrCountdownState extends State<_QrCountdown> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = PairingCode.expirySeconds -
        DateTime.now().difference(widget.createdAt).inSeconds;
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          _remaining = PairingCode.expirySeconds -
              DateTime.now().difference(widget.createdAt).inSeconds;
        });
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
