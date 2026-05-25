# 语音聊天架构调研笔记

## JustTalk 语音场景分析

**典型场景**: 3-5 人开黑打游戏，需要实时语音沟通。

**核心需求**:
- 延迟 <200ms（说话到对方听到）
- 抗丢包（游戏占用带宽时语音不能断）
- 低 CPU 占用（不能影响游戏性能）
- 降噪可选（桌面版，环境噪音相对可控）

## 三种 WebRTC 架构

### P2P Mesh（v0.5 首选）

```
  A ←──→ B
  ↑  ╲ ╱  ↑
  │   ╳   │
  ↓  ╱ ╲  ↓
  D ←──→ C
```

- **原理**: 每人对其他所有人建立独立的 WebRTC 连接
- **上行**: 1 路音频 (Opus 32kbps ≈ 4KB/s)
- **下行**: (N-1) 路音频，4 人时 3 路 ≈ 12KB/s
- **服务器成本**: 0（纯 P2P）
- **延迟**: 最低（无中转）
- **CPU**: 编码 1 路 + 解码 (N-1) 路
- **适合**: 2-6 人
- **JustTalk 适用**: ★★★★★

### SFU（Selective Forwarding Unit，后续升级）

```
       ┌──── SFU 服务器 ────┐
       │ 选择性地转发流      │
       └──┬──┬──┬──┬──┬──┘
          A  B  C  D  E  F
```

- **原理**: 每人推 1 路到 SFU，SFU 选择性转发给其他人
- **服务器成本**: 中等（只转发，不编解码）
- **延迟**: 低（只转发一步）
- **适合**: 5-50 人
- **JustTalk 适用**: ★★★★（后续升级）

### MCU（Multipoint Control Unit，不适合）

- **原理**: 服务器混音所有流，下发混合后的一路
- **服务器成本**: 高（需要解码所有流 → 混音 → 重新编码）
- **延迟**: 较高
- **适合**: 大型会议（50+ 人）

## 技术选型

### webrtc-rs
- Rust 原生 WebRTC 实现
- 源自 Go 的 Pion WebRTC
- 支持 Data Channel + Media
- 项目地址: https://github.com/webrtc-rs/webrtc

### Opus Codec 参数（游戏语音优化）
```
采样率: 48000 Hz
码率: 32000 bps (WB 模式)
帧长: 20ms
特性: FEC (前向纠错) + DTX (静音检测)
复杂度: 5 (中等，节省 CPU)
```

### 音频采集/播放
- Rust: cpal crate（跨平台音频 I/O）
- 缓冲区: 10ms 帧（更低延迟）
- 回声消除: 桌面端一般不需要（戴耳机）

## 如果 P2P Mesh 音频断连怎么办

1. 自动降级：某条连接失败 → 通过其他人 relay（如果还在 Mesh 中）
2. 手动切换：用户可下调音频质量（码率 16kbps 备选）
3. TURN relay：最后手段，走中继服务器

## 参考
- webrtc-rs: https://github.com/webrtc-rs/webrtc
- Opus: https://opus-codec.org/
- cpal: https://github.com/RustAudio/cpal
- WebRTC SFU: https://github.com/webrtc-rs/sfu
- mediasoup-rust: https://mediasoup.org/
