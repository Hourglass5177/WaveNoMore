# BOSS 骨骼导入验收

使用当前工程蛇 BOSS 的 `assets/bosses/animation_studies/snake/boss.spine-json`、`boss.atlas` 和图片，经真实导入确认按钮进入关卡素材库。

通过项：读取多个真实动作；导入候选预览；动作出手标记持久化；素材栏可见；当前游标创建 actor 和动作片段；BOSS 草稿读取默认动作及标记；真实 Spine 驱动定位、回拖与同片段更换动作；ZIP 收集图集与图片；隔离目录重新加载；对象及动作一次撤销。

`Levels/output/spine-import-gpu.log` 为 GPU 操作回归，最终 `LEVEL SPINE IMPORT failures=0` 且没有引擎错误。`Levels/output/spine-import/spine-preview.png` 已人工查看，蛇 BOSS 纹理及姿态正常；`spine-reliability.log`、`spine-animation-regression.log` 为通过的原编辑流程及帧动画回归。

本轮实际素材是 JSON 骨骼；SKEL 入口复用原生二进制读取接口，尚无对应二进制样本实测。多页图集依赖按图集页枚举，当前示例不是多页样本。真实触摸板、跨屏 DPI 与本轮新代码的交付 EXE 未测，未导出程序。
