# 写谱器场景接入与刷新

更新：2026-09-11。适用于当前工程源码；已发布的旧版 EXE 不会自动获得本次能力。

## 在 Godot 中接入

1. 用现有场景编辑器制作世界、角色、编钟和音符场景，通过 `StageVisualTheme` 的对应槽接入；纹理和材质同样使用主题已有字段。
2. 使用视差背景编辑器或 Inspector 保存 `StageBackgroundDefinition`。层深度、子层速度、素材位置、动画和材质沿用正式游戏定义，坐标以 1920×1080 设计画布为准。
3. 在 `StageDefinition` 中填写稳定的 `stage_id`、显示名和排序，关联主题及背景。直接 Resource 引用与现有 `*_resource_path` 懒加载路径均支持，直接引用优先。需要演出时关联 `StageShow`。
4. 在 `content/catalogs/mvp_catalog.tres` 登记关卡。开发时也保留对 `content/stages/*/stage_definition.tres` 的自动发现；正式发布应显式登记。不要在谱面已经使用该场景后随意更改 ID。
5. 保存资源并等待 Godot 完成素材导入，在工程内写谱器点击“刷新场景”，从预览区的列表选择该场景。无需另外维护写谱器主题表或复制关卡代码。

场景仍由正式 `StageRoot` 组装。写谱器读取其表现资源，当前谱面的歌曲、节奏、音符、默认规则和外部试玩流程保持原有来源。没有接入这些槽的独立 `.tscn` 不会自动成为关卡。

主题中 `camera_velocity` 设置镜头持续速度（设计像素/秒），`actors_in_parallax` 将两个角色接入深度 0 的 `actors` 子层，可通过背景子层顺序安排遮挡；编钟和随从仍使用原槽。s08 已开启角色子层，镜头持续速度仍为零。这些表现不再依赖当前谱面的关卡 ID，自制谱引用相同主题即可得到相同装配。

灵均 Spine 攻击保留按住循环、松开播完当前轮、轮内重按继续的行为。写谱预览按输入边界和歌曲时间推进轨道，暂停时冻结，定位时清除旧轨道并从初态重演。自定义场景脚本中的其他自动动画仍需自行接入歌曲时钟；场景引用不会自动改写它们的计时方式。

## 谱面字段

```json
"presentation": {
  "scene_id": "s08",
  "use_scene_show": false,
  "palette_overrides": { "life": "#b93a31" }
}
```

这些是 JSON v2 的可选表现字段，不增加格式版本。每个难度独立保存，新谱使用场景列表的最后一项（目前为 `s08`）且演出关闭。`scene_id` 存在时采用场景；只有 `theme_id` 的旧谱仍按旧主题装配，不附加背景或演出。用户明确选择场景后移除旧 `theme_id`，保留配色与开关。导入能够匹配目录中同一源入口的旧关卡时，会关联场景并关闭演出，原有事件迁移范围不扩展。

演出开启时使用原 `StageShow`，由正式调度器按当前谱面的 tick 和 TempoMap 运行。不会重排原拍点、复制原音乐或扩大谱面尾点。换歌后原教学文字和演出拍点是否适用，需要谱师自行判断。

## 共享入口与运行副本

- `StageCatalogIndex.read` / `sorted_stages`：无场景树依赖的目录读取、开发期发现及排序，由 `ContentCatalog` 与 `ChartSceneLibrary` 共用。
- `ChartSceneLibrary`：主线程按需解析所选表现资源并缓存。`theme_copy` 应用本会话配色；`ChartProjectLoader.make_stage` 复制背景与演出，不改写源资源。
- `ChartProjectLoader.read_project(path, difficulty, all_charts, scene_ids)`：后台入口，使用任务启动时的 ID 快照检查谱面。任务结束后由主线程调用 `check_project_presentation`，再装配正式关卡。同步 `inspect_package`、`read_chart_data`、`load_stage` 已包含表现检查。
- `ChartPackageWriter.write(..., chart_issues)`：后台试玩打包接收主线程对同一谱面快照的检查结果；普通同步调用可省略。后台线程不访问共享表现缓存。

刷新清除表现缓存，重新读取目录，并用 `CACHE_MODE_IGNORE_DEEP` 加载已保存的当前场景依赖，不替换其他会话仍持有的资源。普通编辑复用缓存；颜色修改走现有即时更新。连续切换和刷新合并到下一帧的一次预览重建，旧定位任务被取消，音频位置不变。

首次装入表现资源时检查资源声明的外部依赖，避免 Godot 返回缺图的部分场景后被误认为加载成功；检查结果随表现缓存。缺失资源进入问题列表，可以编辑和保存，不能预览或交付为可玩谱面。修复后显式刷新即可重试。

## 发布与验证

发布给谱师时同步重建 `Chart Studio Windows` 和配套游戏，使用相同的工程素材及目录。导出设置继续携带内置资源，歌曲 ZIP 不携带 `.tscn`、`.tres` 或游戏脚本。旧发布程序不支持运行时读取外部 Godot 工程，更新本地工程也不会改变旧 EXE。

本轮基于队友最新提交 `d2a3086`，使用 Godot 4.7.2 工程运行，没有导出发布包：

- `tests/editor/run_scene_binding_tests.gd`：旧谱兼容、新谱默认值、资源副本、Replay、难度历史、保存恢复、ZIP、后台读取与打包、演出定位、深层刷新、缺失依赖，以及真实灵均角色的层级、暂停和回拖；已加入写谱器测试入口。
- `tests/integration/stage/run_lingjun_attack_tests.gd`：保留队友新增的攻击循环、松开收尾与再次按住行为。
- `tests/editor/run_trial_flow_tests.gd`：使用 s08 验证正式游戏启动、背景与演出装配、重试和加入本地库后的加载。
- 现有写谱器基础、本地谱面、预览冻结与视差测试作为相关回归。
- OpenGL 实际渲染检查 1280×720、1440×900 的场景控件和 s08 预览。截图保存于 `builds/visual-review/scene-binding/`，测试日志保存于 `builds/scene-*.log`。

验证结果：场景接入 59 项、视差 118 项、写谱器基础 41 项、正式试玩流程 31 项、预览冻结 14 项全部通过；本地谱面、音符光效和灵均攻击回归也通过。场景接入测试同时通过 headless 和 OpenGL 实际渲染运行。

工程导入仍报告两份 `screen_half_material_split` Shader 的 UID 重复。正式试玩流程测试退出时报告两个音频对象未释放（`AudioStreamWAV` 与 `AudioStreamPlaybackWAV`）；测试断言通过，本轮没有调整音频生命周期。这些诊断保留在日志中。

本轮检查覆盖工程内加载；双程序发布包的资源收录仍需在下一次明确要求打包时验证。
