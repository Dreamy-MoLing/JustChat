# 加密方案调研笔记

## 核心原则

**不重复造轮子。加密的每个细节都可能是漏洞。**

## Signal Protocol (推荐)

### Double Ratchet 机制
- 每条消息用不同密钥
- 密钥定期更新（ratchet advance）
- 破解一条消息 ≠ 破解所有消息
- 前向保密 + 后向保密

### 为什么选 Signal
- libsignal 由 Signal 基金会维护，经过最严格的安全审计
- 用 Rust 实现（`libsignal-protocol` crate）
- 已被 WhatsApp、Skype、Google Messages 采用
- 数十亿设备验证，没有已知设计缺陷

### 接入步骤
1. 生成注册 ID + 身份密钥对
2. 生成预密钥束（PreKeyBundle）
3. 通过信令服务器交换预密钥
4. 建立 Double Ratchet 会话
5. 之后每条消息自动 ratchet

## 备选方案

### noise-protocol
- 更轻量，更适合底层网络协议
- libp2p 使用 noise 做传输加密
- 应用层消息加密需要自己封装
- 结论: 备选，适合想做更底层控制的场景

### NaCl/libsodium (crypto_box)
- 极其简单：一次公钥交换，之后直接 encrypt/decrypt
- 缺点：无前向保密，密钥泄露影响所有历史消息
- 结论: 不推荐用于聊天

### 自研 (AES-GCM + ECDH)
- 绝对不做。这不是一个人能干好的事。

## 加密接口设计模式

```rust
// Step 1: 定义 trait（v0.1 就写好）
trait MessageEncryptor {
    fn encrypt(&self, plain: &[u8]) -> Result<Vec<u8>>;
    fn decrypt(&self, cipher: &[u8]) -> Result<Vec<u8>>;
}

// Step 2: v0.1 用空实现
struct NoopEncryptor;
impl MessageEncryptor for NoopEncryptor { /* pass-through */ }

// Step 3: v0.2 替换为真正的加密实现
struct SignalEncryptor { session: Session, ... }
impl MessageEncryptor for SignalEncryptor { /* libsignal */ }

// Step 4: 客户端通过配置文件切换
let encryptor: Box<dyn MessageEncryptor> = match config.encryption {
    EncryptionMode::None => Box::new(NoopEncryptor),
    EncryptionMode::Signal => Box::new(SignalEncryptor::new(...)),
};
```

## 注意事项
- 加密前先压缩？（压缩会泄露内容长度信息 → CRIME/BREACH 攻击 → 不推荐）
- 消息时间戳也应该加密
- 元数据（谁在和谁聊天）目前几乎所有 E2EE 方案都无法隐藏 → Signal 的 Sealed Sender 部分缓解

## 参考
- libsignal: https://github.com/signalapp/libsignal
- Double Ratchet 规范: https://signal.org/docs/specifications/doubleratchet/
- noise protocol: https://noiseprotocol.org/
