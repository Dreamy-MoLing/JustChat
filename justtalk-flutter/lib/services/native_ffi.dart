// Dart FFI 绑定 — 调用 Rust justtalk-core 引擎。
//
// 使用 `dart:ffi` 加载 libjusttalk_core.so 并调用 C ABI 函数。
// 所有复杂类型通过 JSON 字符串序列化跨 FFI 边界。

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ── C 函数签名 ──

typedef JtInitNative = Pointer<Utf8> Function(Pointer<Utf8> storagePath);
typedef JtInitDart = Pointer<Utf8> Function(Pointer<Utf8> storagePath);

typedef JtPollNative = Pointer<Utf8> Function();
typedef JtPollDart = Pointer<Utf8> Function();

typedef JtCallNative = Pointer<Utf8> Function(Pointer<Utf8> methodJson);
typedef JtCallDart = Pointer<Utf8> Function(Pointer<Utf8> methodJson);

typedef JtFreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef JtFreeStringDart = void Function(Pointer<Utf8> ptr);

/// Rust FFI 桥接
class NativeEngine {
  static NativeEngine? _instance;
  late final DynamicLibrary _lib;

  late final JtInitDart jtInit;
  late final JtPollDart jtPollEvents;
  late final JtPollDart jtPollCommands;
  late final JtCallDart jtCall;
  late final JtFreeStringDart jtFreeString;

  bool _loaded = false;

  NativeEngine._();

  factory NativeEngine() {
    _instance ??= NativeEngine._();
    return _instance!;
  }

  bool get isLoaded => _loaded;

  /// 加载原生库。
  ///
  /// 查找顺序：
  /// 1. `libjusttalk_core.so`（系统路径或 LD_LIBRARY_PATH）
  /// 2. 同目录下的 `native/linux/libjusttalk_core.so`（开发模式）
  void load() {
    if (_loaded) return;

    try {
      // 尝试系统路径
      _lib = DynamicLibrary.open('libjusttalk_core.so');
    } catch (_) {
      // 尝试本地开发路径
      try {
        _lib = DynamicLibrary.open('native/linux/libjusttalk_core.so');
      } catch (_) {
        // 尝试可执行文件目录
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        try {
          _lib = DynamicLibrary.open('$exeDir/lib/libjusttalk_core.so');
        } catch (e) {
          throw StateError('无法加载 libjusttalk_core.so: $e');
        }
      }
    }

    _bindFunctions();
    _loaded = true;
  }

  void _bindFunctions() {
    jtInit = _lib
        .lookupFunction<JtInitNative, JtInitDart>('jt_engine_init');

    jtPollEvents = _lib
        .lookupFunction<JtPollNative, JtPollDart>('jt_poll_events');

    jtPollCommands = _lib
        .lookupFunction<JtPollNative, JtPollDart>('jt_poll_commands');

    jtCall = _lib.lookupFunction<JtCallNative, JtCallDart>('jt_call');

    jtFreeString =
        _lib.lookupFunction<JtFreeStringNative, JtFreeStringDart>(
            'jt_free_string');
  }

  // ── 辅助方法 ──

  /// 调用 C 函数并解析返回的 JSON 字符串
  String _callAndFree(Pointer<Utf8> Function() func) {
    final ptr = func();
    final result = ptr.toDartString();
    jtFreeString(ptr);
    return result;
  }

  String _callWithArgAndFree(
      Pointer<Utf8> Function(Pointer<Utf8>) func, String arg) {
    final argPtr = arg.toNativeUtf8();
    final resultPtr = func(argPtr);
    final result = resultPtr.toDartString();
    jtFreeString(resultPtr);
    calloc.free(argPtr);
    return result;
  }

  // ── 公开 API ──

  /// 初始化引擎
  Map<String, dynamic> init(String storagePath) {
    final resultJson = _callWithArgAndFree(jtInit, storagePath);
    final result = jsonDecode(resultJson) as Map<String, dynamic>;
    if (result['ok'] != true) {
      throw StateError('引擎初始化失败: ${result['error']}');
    }
    return result;
  }

  /// 获取待处理事件列表
  List<dynamic> pollEvents() {
    final resultJson = _callAndFree(jtPollEvents);
    return jsonDecode(resultJson) as List<dynamic>;
  }

  /// 获取待处理命令列表
  List<dynamic> pollCommands() {
    final resultJson = _callAndFree(jtPollCommands);
    return jsonDecode(resultJson) as List<dynamic>;
  }

  /// 调用引擎方法
  Map<String, dynamic> call(String method, [Map<String, dynamic>? params]) {
    final request = jsonEncode({
      'method': method,
      if (params != null) 'params': params,
    });
    final resultJson = _callWithArgAndFree(jtCall, request);
    final result = jsonDecode(resultJson) as Map<String, dynamic>;
    if (result['ok'] != true) {
      throw StateError(
          '引擎调用 $method 失败: ${result['error'] ?? 'unknown'}');
    }
    return result;
  }

  /// 释放引擎资源
  void dispose() {
    _loaded = false;
  }
}
