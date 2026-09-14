# 随从动画正式接入验证

日期：2026-09-14。环境：Godot 4.7.2 / Spine 4.3，Compatibility / OpenGL 3.3，RTX 4060 Laptop。未构建发行程序。

## 本次结果

三只随从已接入关外装备和正式 StageRoot。按最新审看反馈，默认显示从约 80 px 调整为 **100 px**，生界偏移从 `(-96,70)` 调整为 **`(-112,70)`**，死界中心对称。1920×1080 设计画布中，两侧锚点分别为 `(158,305)`、`(1762,775)`。

| 检查 | 结果 |
| --- | --- |
| 编辑器导入、脚本解析 | 无错误 |
| `run_pet_runtime_tests.gd` | 159 项通过 |
| `run_pet_animation_study_tests.gd` | 98 项通过 |
| `run_pet_tests.gd` | 260 项通过 |
| `run_save_tests.gd` | 13 项通过 |
| `run_menu_navigation_tests.gd` | 49 项通过 |
| `run_develop_merge_tests.gd` | 通过，双 Hold / 调频与外部时钟行为保持 |
| `run_preview_frame_tests.gd` | 通过，内嵌预览仍无玩家装备，暂停、定位和后台恢复正常 |
| Compatibility 实拍 | 三只各 174 帧，30 fps，覆盖双方常态、技能、主角攻击及死亡；另采样 1280×720 布局 |

接入回归覆盖两种形态的装备、保存重开、关外卸下、重试固定形态；单侧与双侧来源、密集触发、零伤害、伤害组去重、致命优先；苹果蛇有效起手、漏接、续按、暂停重臂和进阶提档。对照 30 / 60 / 144 Hz、分批重演与直接定位，骨骼位置和变换误差在 0.001 设计像素容差内；喷火、灰烬和混合状态均按相同时间恢复。也检查了负时间倒计时及提前起手。

消费随从表现事件前后的判定记录、实际技能收益和 Replay 摘要一致。没有调整判定窗、得分、伤害公式、装备 ID 或技能描述。原有菜单测试清理阶段调用了已经删除的 `_discover_stage_packages()`，本次去掉该过时调用，保留目录滚动与弹窗焦点检查。

`run_pet_tests.gd` 有一次 Headless 退出报告两个音频对象未释放；同套件的其他运行无此警告。新增装备回归在换页前停止测试音频，最终运行无泄漏警告；此次没有修改音频实现。

## 实拍与审看

输出位于不入 Git 的 `build/pet-runtime/`：

- `selection.png`：彩色原画图标、名称和装备状态。
- `companions-in-game.gif`：三只随从关内双侧对照，按正式姿态裁排，20 fps 缩图。
- `both-worlds.png`：常态双侧对照，保留原始像素比例。
- `runtime-keyposes.png`：技能时段、死亡下沉、消逝关键帧。
- `{nu_tu_fu,yi_huo_she,gui_jin_yang}/0000.png`～`0173.png`：完整 1920×1080 实拍原帧，30 fps。
- `*-1280.png`：1280×720，沿用正式窗口的设计画布缩放。

实际画面中，生界保持原画颜色；死界骨骼、苹果蛇喷火和灰烬均去色，亮度为 65%。检查了黑色蝠翼、浅色羊毛、蛇颈及喷火的辨识度，主角攻击时没有遮住随从主体。随从完成 2.05 秒消逝后无残留。审看中的致命事件由测试脚本从领域伤害入口送入，使用正式协调层同时驱动主角和随从；技能展示使用真实 Hold 输入、额外加分或减伤事件。

重新采样：

```powershell
godot --path . --rendering-method gl_compatibility --minimized --script tools/pet_animation/capture_runtime.gd
python tools/pet_animation/package_runtime_review.py
```

只检查布局可在第一条后加 `-- --layout`；只采样某只可加 `-- --pet=yi_huo_she`。工具使用隔离审看存档，并手动提交绘制，最小化窗口也能采样。正式游戏不引用这些工具脚本。

资源、侧别事件及时间接口见[随从系统](pet-system.md)，骨骼素材与生成方式见[随从动画](pet-animation-studies.md)。
