# DisplayPilot

自用的 macOS 菜单栏显示器工具：**柔性 HiDPI 缩放** + **软件/硬件亮度**，界面用 GitHub Octicons 图标，中英双语。

替代 BetterDisplay / Crisp 在本机的用途，但更轻：没有虚拟屏、PiP、串流那些用不上的功能，也没有授权码。

## 功能

- **柔性 HiDPI 缩放**：为显示器注入 61 档等距缩放梯（原生宽 16 点一档直到 50%，全部 2× 超采样），写 `/Library/Displays/.../Overrides` 后立刻重枚举，**不需要重启也不用拔线**。内容与盘上一致时不会重复弹管理员密码。
- **软件调光**：伽马表压暗画面，不碰显示器背光，**与 DCR 模式不冲突、不闪**。唤醒、改分辨率、换色彩描述文件后自动重放。
- **硬件调光（DDC/CI）**：通过 `IOAVService` 写 VCP 0x10；每块屏可独立选择 `自动 / 强制硬件 / 强制软件`，`自动` 每会话只探测一次。
- **亮度键接管**：拦截 F1/F2（需要辅助功能权限），并显示屏幕底部 OSD。
- **自定快捷键**：⌥⌘↑/↓ 调亮度、⌥⌘1…3 应用预设（Carbon 热键，不需要任何权限）。
- **预设**：一键切换分辨率 + 亮度。
- **安全网**：改动前自动备份原 override 到 `~/Library/Application Support/DisplayPilot/backups/`；面板里有「还原原生」回到系统原始模式表。

## 环境要求

- macOS 26（Tahoe）或更新
- Apple Silicon
- 构建需要 Xcode 26 + [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

## 构建 / 运行

```sh
make run      # 生成工程 → 编译 → 用本机证书签名 → 启动
make test     # 跑单元测试 + 集成校验
make stop     # 退出
```

签名用本机已有的自制证书 `Codex Patched Signing`（`Makefile` 里的 `SIGN_IDENTITY`），
这样辅助功能授权不会因为每次重编译失效。换证书改这一行即可。

## 权限

| 功能 | 需要什么 | 为什么 |
| --- | --- | --- |
| 调亮度 / 切分辨率 | 无 | 都是公开 API |
| 启用平滑缩放 | 一次管理员密码 | 要往 `/Library/Displays` 写 override 文件 |
| F1/F2 亮度键 | 辅助功能 | 用 CGEventTap 拦截媒体键并吞掉系统默认行为 |

没给辅助功能权限时，F1/F2 走系统默认逻辑，⌥⌘↑/↓ 仍然可用。

## 实现要点

- override 文件必须同时写 `DisplayPixelDimensions` 与 `default-resolution`，否则 macOS 会把缩放档位当成真实输出时序发给显示器，**画面会留黑边**。
- 重枚举用 IOKit 的 `IOServiceRequestProbe`（匹配 `IODisplayConnect` 的 vendor/product），写完立刻生效。
- DDC 走 `IOAVService` 的私有 I2C 通道，DDC/CI 报文与校验和按规范构造；只在用户操作时发命令，不做后台轮询。
- 显示器身份用 ColorSync 的 UUID（跨重连稳定），每屏的亮度/策略/预设都按它存。

## 已知限制

- 只在本机（macOS 26 + Apple Silicon）验证过；私有 API 随系统更新有失效风险。
- 软件调光走伽马表，会影响截图/录屏的观感（和 BetterDisplay 的软件调光同理）。
- 硬件调光在部分显示器的 DCR 模式下会与自动背光打架（本机这台屏已预置成强制软件调光）。

## 分享给别人用（重要）

这个 App 的自用版**没有做代码签名公证**，别人直接拷 .app 会被 Gatekeeper 拦。三种可行姿势：

1. **让朋友自己编译**（最省事）：装 Xcode + `brew install xcodegen`，`git clone` 后 `make run`。
   `Makefile` 会自动挑签名证书：本机有自制证书就用它，没有就退回 ad-hoc 签名。
2. **做成正式发布**：需要 Apple 开发者账号（$99/年），用 Developer ID 签名 + 公证；私有 API 决定了它不能上架 App Store。
3. **只是自己几台机器用**：把自制证书导出成 .p12，在目标机器导入后用同一个证书签名，辅助功能授权才不会每次重编译失效。

朋友第一次打开需要知道三件事：

- 屏幕录制/辅助功能这些权限是**每台机器单独授权**的；F1/F2 亮度键要勾「辅助功能」，不给也能用 ⌥⌘↑/↓。
- 平滑缩放要写 `/Library/Displays/.../Overrides`，会弹一次管理员密码；写之前会自动备份原文件。
- 显示器差异很大：DDC 有的显示器要特殊命令、有的 KVM/扩展坞不转发 DDC，识别不到就会自动退回软件调光（面板里也能手动切）。
- 「已知机型怪癖表」在 `Sources/Core/SettingsStore.swift` 的 `knownQuirks`，命中 vendor+product 才会生效；遇到新的"DDC 会闪"的显示器，往里加一行即可。

## 第三方

- 图标：[GitHub Octicons](https://github.com/primer/octicons)（MIT）
- DDC/CI 与媒体键部分参考了 [Crisp](https://github.com/didriksg/Crisp)（MIT）

详见 `THIRD_PARTY_NOTICES.md`。本项目自身以 MIT 发布。
