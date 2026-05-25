# P2P NAT 穿透调研笔记

## 问题本质
两个家庭路由器后面的电脑如何直接建立 TCP/UDP 连接？

## NAT 类型与穿透成功率

| NAT 类型 | 穿透难度 | libp2p dcUTR | STUN | TURN |
|---------|----------|-------------|------|------|
| 全锥形 NAT | 容易 | ✅ 90% | ✅ | ✅ (但不必要) |
| 受限锥形 NAT | 中等 | ✅ 65% | ✅ | ✅ (但不必要) |
| 端口受限锥形 NAT | 较难 | ⚠️ 50% | ⚠️ | ✅ |
| 对称 NAT | 几乎不可能 | ❌ 5% | ❌ | ✅ (唯一方案) |

注：中国家庭宽带以锥形 NAT 为主，校园网/企业网多为对称 NAT。

## 技术方案对比

### libp2p (Rust)
- DCUtR 协议: relay 保底 + 直接打洞升级
- 内置 AutoNAT 检测 NAT 类型
- Kademlia DHT 实现无中心节点发现
- 缺点: 库体量大，学习曲线陡峭
- 结论: **中长期采用**

### WebRTC Data Channel
- 基于 ICE 框架，STUN/TURN 一体化
- 浏览器原生支持（未来 Web 版可复用）
- NAT 穿透比 libp2p 更成熟（Google 数年投入）
- 缺点: 数据通道略重（DTLS 握手）
- 结论: **v0.1 直接用 webrtc-rs 的数据通道，更简单**

### 最终方案
- v0.1: WebRTC Data Channel（更简单、穿透更好）
- 以后需要 DHT 发现时再接入 libp2p
- TURN 兜底: coturn 自建

## 参考
- libp2p hole punching tutorial: https://docs.rs/libp2p/latest/libp2p/tutorials/hole_punching/
- webrtc-rs: https://github.com/webrtc-rs/webrtc
- coturn: https://github.com/coturn/coturn
