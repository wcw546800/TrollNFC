# TrollNFC

iOS NFC读取、写入和模拟工具，专为TrollStore环境设计。

## 功能特性

### ✅ 已实现
- **NFC读取**：支持多种标签类型
  - Mifare Classic (1K/4K)
  - Mifare Ultralight
  - Mifare DESFire
  - ISO 14443-A/B
  - ISO 15693
  - FeliCa
  - ISO 7816
  - NDEF

- **完整Dump**：读取Mifare Classic全部扇区数据
  - 自动尝试常用密钥
  - 支持Key A/B认证

- **NDEF读写**：读取和写入NDEF格式数据
  - 文本记录
  - URL记录
  - 智能海报

- **卡片管理**
  - 本地保存读取的卡片
  - 导出为JSON格式
  - 导出为Flipper Zero格式 (.nfc)

### ⚠️ 实验性功能
- **NFC模拟**：通过私有API尝试卡片模拟
  - 依赖iOS私有框架
  - 受Secure Element硬件限制
  - 可能不适用于所有设备/iOS版本

## 系统要求

- iOS 15.0+
- iPhone 7 或更新（需要NFC硬件）
- TrollStore 已安装

## 安装

### 方式一：从IPA安装
1. 下载最新的 `.ipa` 文件
2. 通过TrollStore安装

### 方式二：从源码编译
1. 克隆仓库
2. 用Xcode打开 `TrollNFC.xcodeproj`
3. 编译为Release版本
4. 使用TrollStore签名并安装

## 项目结构

```
TrollNFC/
├── TrollNFC.xcodeproj/
├── TrollNFC/
│   ├── Sources/
│   │   ├── TrollNFCApp.swift      # 应用入口
│   │   ├── NFCManager.swift       # NFC核心管理器
│   │   └── NFCEmulator.swift      # NFC模拟器(实验性)
│   ├── Views/
│   │   └── ContentView.swift      # SwiftUI界面
│   ├── Models/
│   │   └── NFCCard.swift          # 数据模型
│   ├── PrivateHeaders/
│   │   └── NFCPrivate.h           # 私有API声明
│   ├── Info.plist
│   └── TrollNFC.entitlements
└── README.md
```

## 使用的Entitlements

TrollStore应用需要以下特殊权限：

```xml
<!-- 标准NFC权限 -->
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
    <string>TAG</string>
</array>

<!-- TrollStore扩展权限 -->
<key>com.apple.nfc.nfcprivate</key>
<true/>
<key>com.apple.nfc.nfchardwaremanager</key>
<true/>
```

## 私有API说明

本项目使用以下私有框架/API：

| 框架/类 | 用途 |
|--------|------|
| NFHardwareManager | 底层NFC硬件控制 |
| NFSecureElementManager | Secure Element访问 |
| NFCMiFareTag (私有扩展) | Mifare认证/读写 |

**警告**：私有API可能在任何iOS更新中发生变化或被移除。

## 关于NFC模拟

iOS对NFC模拟有严格限制：

1. **Secure Element**：苹果将NFC模拟功能锁定在硬件安全芯片中
2. **Apple Pay独占**：只有苹果授权的功能才能使用SE进行NFC模拟
3. **无HCE**：iOS不原生支持Host Card Emulation

本项目的模拟功能是**实验性的**，通过以下方式尝试：
- 动态加载私有框架
- 尝试调用底层硬件管理器
- 实验性HCE实现

**实际效果取决于设备和iOS版本，很可能无法正常工作。**

## 已知限制

1. **Mifare Classic读取**：iOS原生不支持完整的Mifare Classic操作，本项目通过私有API扩展
2. **加密卡**：无法读取使用非标准密钥加密的扇区
3. **写入限制**：写入功能需要谨慎使用，错误操作可能损坏卡片
4. **模拟功能**：受硬件限制，大部分设备无法使用

## 常见问题

**Q: 为什么无法读取我的门禁卡？**
A: 门禁卡通常使用自定义密钥加密，需要知道正确的密钥才能读取。

**Q: 模拟功能为什么不工作？**
A: NFC模拟受iOS硬件限制，即使在TrollStore环境下也可能无法突破Secure Element的保护。

**Q: 支持哪些iOS版本？**
A: 需要iOS 15.0+，且TrollStore支持的iOS版本（通常14.0-17.0）。

## 免责声明

本项目仅供学习和研究目的。请勿将本工具用于任何非法目的。使用者需自行承担使用本工具的风险和责任。

## 许可证

MIT License

## 致谢

- TrollStore项目
- iOS NFC逆向工程社区
- Flipper Zero团队（格式兼容参考）
