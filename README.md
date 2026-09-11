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

## 第三方

- 图标：[GitHub Octicons](https://github.com/primer/octicons)（MIT）
- DDC/CI 与媒体键部分参考了 [Crisp](https://github.com/didriksg/Crisp)（MIT）

详见 `THIRD_PARTY_NOTICES.md`。本项目自身以 MIT 发布。
