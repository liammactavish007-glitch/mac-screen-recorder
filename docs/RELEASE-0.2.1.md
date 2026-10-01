# 本机录屏 v0.2.1 · 首个公开测试版

独立 macOS App + 完整源码 + 可选 Codex skill，采用 MIT 许可。录制画面、系统声音及可选麦克风，无需 Codex、大模型 API、登录或网络服务。

## 下载哪个文件

- **App：** `MacScreenRecorder-0.2.1-macos-arm64.zip`，解压后运行 `本机录屏.app`。
- **skill：** `mac-screen-recorder-skill-0.2.1.zip`，解压后把 `mac-screen-recorder` 文件夹放入你的 skills 目录。App 需另外安装。
- **完整源码：** `mac-screen-recorder-source-0.2.1.zip`，含构建脚本和安装说明。
- **校验：** `SHA256SUMS.txt`。

## 使用要求与限制

仅支持 Apple Silicon Mac、macOS 15+；当前界面为中文。App 为 ad-hoc 本机签名，**没有 Apple Developer ID 签名或公证**，其他 Mac 下载后可能出现 Gatekeeper 拦截或提示；不建议关闭系统安全机制，可审查源码后自行编译。

系统声音默认开、麦克风默认关；屏幕 / 系统声音和麦克风权限由 macOS 管理。默认输出 H.264 MP4 和相邻 JSON 报告。

快捷键：`Control + Shift + R` 开始 / 停止，`Control + Shift + S` 显示窗口。关闭窗口可菜单栏常驻，完全退出后快捷键不工作。

本机系统声音录制已有测试证据；真实键盘快捷键、双声源录制及其他 Mac 分发仍需进一步验证。本版未实现自动登录启动、退出后快捷键唤起、暂停录制或独立音轨导出。详细边界见仓库 `docs/VALIDATION.md`。
