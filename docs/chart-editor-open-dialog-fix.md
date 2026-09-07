# 打开项目对话框修复

2026-09-07：修复选择 song.json 后文件名为空、双击无响应。

原过滤规则为 `song.json ; 歌曲项目`。Godot FileDialog 对精确名称会预选条目，但未同步文件名；再次单击已选条目不会补发选择事件。改为 `*.json`，过滤说明提示选择 song.json；加载失败时显示“打开项目失败”及具体原因，路径保留在提示中。

验证使用同一实际渲染脚本、同一非空示例目录，对比旧过滤规则与新规则：旧规则的单击文件名、双击加载、音符加载三项失败，新规则四项检查全部通过。鼠标事件注入文件对话框本身，没有直接调用项目加载函数。headless 回归使用 ItemList 选择/激活信号，不等同于实际鼠标检查。

回归入口：`tests/editor/run_open_dialog_tests.gd`。传入 `--legacy-filter` 可复现旧过滤行为。引擎实现参考：[Godot FileDialog 源码](https://github.com/godotengine/godot/blob/4.7/scene/gui/file_dialog.cpp)。
