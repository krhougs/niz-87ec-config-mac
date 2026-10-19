# NIZ X87EC macOS 配置工具

[English](README.md)

NIZ（宁芝）X87EC 静电容键盘的原生 macOS 配置工具，用来替代官方只有 Windows 版的 `X87EC.exe`。
协议是从官方 Windows 工具逆向出来的，并在真机上验证过。

![按键](docs/keys.png)

## 功能

- **按键改键**，支持基础层和 Fn 层：
  - 单键与组合键（修饰键开关 + 主键，比如 Ctrl + C）
  - 按住连发（官方叫"模拟击键"），间隔可调
  - 宏：播放 N 次 / 按住播放 / 按一下开始再按停止，可以统一延时，也可以每步单独设延时
  - 多媒体键、鼠标键和键盘功能键（背光、蓝牙 1–5、Win/Mac 切换、Fn 锁、游戏模式等）
- **可视化选键**：在键盘图上点、按分类浏览、按名字搜索，或者直接按一下实体键。
- **单键 RGB 背光**：给按键上色、按颜色选键、取色（⌥ + 点击）。
- **击键统计**：用热力图显示键盘里存的每个键的累计按键次数。
- **配置文件**：以 JSON 保存和加载；另有命令行工具 `nizctl`，可以备份和恢复。
- 写入前会检查：如果新布局会导致没有 Fn 键、或者切不回出厂布局，会先提示。

| 选键面板 | 背光 |
|---|---|
| ![选键](docs/picker.png) | ![背光](docs/lighting.png) |

## 支持的硬件

在 **X87EC(S)BLe**（USB 名称 `X87EC-RGB`，固件 `V1.3.1`）上测试过。
官方工具支持的其他 X87EC 型号（USB `0483:5031`、`5131`、`5231`、`5331`）理论上也能用，但没有测试。
只支持 USB 连接，不支持蓝牙。

## 编译

需要 macOS 14+、Xcode 15+（Swift 5.10）。

```sh
git clone https://github.com/krhougs/niz-87ec-config-mac.git
cd niz-87ec-config-mac
./build-app.sh          # 生成 dist/NIZ Config.app 和 dist/nizctl
swift test              # 用抓到的真机数据包跑协议测试
```

App 只做了 ad-hoc 签名。第一次打开时右键选"打开"，或者执行
`xattr -dr com.apple.quarantine "dist/NIZ Config.app"`。

## 使用

### 1. 把键盘切到 Win 模式

在 **Mac 模式**下，键盘会伪装成 Apple 键盘，并**隐藏配置接口**，任何工具都连不上。

1. 按住 **Fn**，再按 **左 Alt**（底排左数第三个键）。
2. **拔掉 USB 线再插上**。模式要重新枚举 USB 之后才会生效。

App 检测到键盘处于 Mac 模式时会显示上面的步骤；切到 Win 模式后会自动连接。
改完想回 Mac 模式，再做一遍同样的操作就行。

### 2. 修改并写入

打开 **NIZ Config**，连接后会自动读取按键、背光和计数。改完后点工具栏的
**Write Keys**（写入按键）或 **Write Lighting**（写入背光）。还没写入的键会显示成橙色。

### 出厂布局与编程布局

键盘里存了**两套布局**，用 **Fn + Pause** 在两者之间切换：

- **出厂布局**：固定不变。
- **编程布局**：本工具（和官方工具）写入的就是这一套。

写入总是写到编程布局；**读取（Read）** 读到的是当前正在用的那一套。
如果写入时键盘正处于出厂布局，App 会提示你，按 **Fn + Pause** 就能用上新布局。

## 命令行

```sh
dist/nizctl info                 # 型号和固件版本
dist/nizctl keys [层]            # 打印按键表
dist/nizctl lights               # 每个键的颜色
dist/nizctl counters             # 击键计数，按次数从多到少
dist/nizctl backup my.json       # 备份按键和背光
dist/nizctl restore my.json      # 写入按键和背光
dist/nizctl restore-keys my.json
dist/nizctl restore-lights my.json
```

动手之前建议先备份：`dist/nizctl backup original.json`。

## 说明与限制

- 每套布局在固件里有 6 层。原厂状态下第 3–6 层是基础层/Fn 层的拷贝（推测给其他连接模式用，未确认）。
  **写入时没有发送的层会被清空。** 官方工具只写 2 层，所以本工具会写满 6 层，把基础层和 Fn 层复制到第 3–6 层。
- 宏和连发键按官方工具的编码实现，也通过了往返测试，但实际使用的验证比普通改键少。
- 故意没有实现固件升级。
- 少数功能码的名称（比如 `0xB0`–`0xB2`）来自官方工具的表，在某些型号上可能对不上。

## 协议

USB 标识、命令、记录格式、键位编号和键码，见 [PROTOCOL.md](PROTOCOL.md)（英文）。

## 目录结构

```
Sources/NIZKit     HID 通信、协议编解码、键码、键位布局（不含 UI）
Sources/NIZConfig  SwiftUI App
Sources/nizctl     命令行工具
Tests/NIZKitTests  用真机抓包数据做的编解码测试
```

## 免责声明

本项目是非官方的，与 NIZ 无关。写入键盘的风险由使用者自己承担，请先用 `nizctl backup` 备份。
