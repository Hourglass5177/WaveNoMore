# 编钟音游核心玩法原型

该目录包含四个浏览器玩法验证原型：

1. `life-death-interference/`：生死相干 2.4——生、死双钟演奏不同节奏，以拍频驱动骨白相纹扫过两界并击破白色魂形。

2. `star-tide/`：星潮共鸣——敲钟产生扩散声浪，一次输入串联后续目标。
3. `star-trace/`：牵星成宿——按住并拖动巫火，在定时星点处完成星宿轨迹。
4. `celestial-disk/`：巡天星盘——转动星盘，在自动钟击时让妖星对准固定钟光。

## 运行

推荐双击 `Prototype/启动Web原型.cmd` 启动本地服务器并打开统一入口；生死相干原型需要通过 HTTP 读取本地真实音乐，不能直接使用 `file://`。

在 PowerShell 中运行：

```powershell
.\Prototype\serve.ps1
```

或者在项目根目录直接运行：

```powershell
python -m http.server 4173 --directory Prototype
```

然后访问：

```text
http://localhost:4173/
```

四个原型全部使用原生 HTML、CSS、Canvas 与 Web Audio，不依赖 npm 包。生死相干 2.4 使用仓库内的 CC0 本地音乐，其余表现为程序化占位；浏览器要求用户主动点击开始按钮后才会启用声音。

自动化与浏览器验收结果见 [`VALIDATION.md`](VALIDATION.md)。

## 原型边界

- 目标是验证核心输入是否成立，不代表最终UI或数值方案。
- 四版均由单一歌曲时钟驱动，视觉位置不作为判定真值。
- 编钟音高由内置乐曲配置，玩家不需要选择音高。
- 二十八宿作为Boss与星图母题；二十四节气作为视觉时令，不强行映射成输入规则。
