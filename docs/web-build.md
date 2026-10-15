# Web 在线试玩构建

使用 Godot 4.7.2 的 `Web Release` 预设，启用 GDExtension 与多线程，沿用 Compatibility / WebGL 2。Spine 使用工程已有的 WebAssembly 库；Windows 专用震动扩展不导出，手柄按键和摇杆仍由 Godot 输入系统处理。

## 构建与打包

安装同版本 `web_dlink_release.zip` 导出模板。在 Game 目录运行：

```powershell
& 'F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --export-release 'Web Release' 'builds/web/index.html'
python tools/web/package.py
```

生成 `builds/冥河，冥河！v1.0.1-Web.zip`，包名读取工程版本。指定发布位置时，使用 `package.py --directory <Web导出目录> --output <ZIP路径>`。主页面必须与 JS、WASM、PCK、Spine WASM 和音频 worklet 一起部署。Web 使用 `tools/web/shell.html`：顶部独立栏提供“全屏游玩”，点击后仅游戏画布进入全屏，按 Esc 退出。窗口模式为顶部栏留出空间，画布跟随剩余区域及设备像素比调整；游戏继续以 1920×1080 的 KEEP 模式等比居中，比例不同则留边，完整显示画面。网页设置仍显示“跟随窗口”，原有全屏选项也可用。

## 部署

目标是桌面浏览器，使用支持 WebGL 2、WebAssembly 和 SharedArrayBuffer 的 Chromium 浏览器。线上使用 HTTPS，并给整个游戏目录返回：

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: same-origin
```

WASM 的 MIME 类型为 `application/wasm`。包含 Nginx 示例与静态托管 `_headers`；若平台不支持响应头或大文件，应选择可配置的服务器。不要直接双击 HTML，也不要在未配置权限及隔离头的第三方 iframe 中嵌入。

本地已安装 Python 3 时，运行包内 `本地试玩.cmd`，打开 `http://localhost:8067/`。服务器只监听本机；正式发布使用自己的 HTTPS 服务器。本次仅打包，不部署公网。

## 体积与浏览器限制

目前 PCK 约 1.33 GiB，包含三关资源和开场 PV。需完整下载后启动，首次加载时间和内存占用较高，本版不宣称适合手机或低内存设备。PV 沿用 Theora；浏览器解码效率可能低于桌面版，可按原有跳过键进入选关。

声音需要用户交互解锁。存档保存在浏览器站点数据中，与 Windows 存档独立，清除站点数据会丢失。浏览器手柄震动不使用 Windows 原生扩展。线上音频延迟、真实手柄调频及不同浏览器的手感仍需实际设备验证。

## 本机验证范围

在有实际图形窗口的 Chromium 中检查启动引导、PV 与跳过、选关、第一关资源装载、Spine 角色、动态背景、键盘输入、失败结算；修复画布偏下后以 1280×720 检查显示。最终包另检查设置、暂停和尺寸变化。浏览器控制台与导出日志用于核对脚本及资源错误，不以导出成功代替运行检查。未把该结果视为完整三关通关或真实性能、音频端到端延迟验收。

参考：[Godot Web 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)、[Web 导出选项](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformweb.html)。
