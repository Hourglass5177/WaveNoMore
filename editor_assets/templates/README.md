# 写谱器模板

此目录只存放新谱和演出轨模板，不进入发行包。

- 新建文档内置完整的 `StageDefinition` / `SongDefinition` / `SongChart` / `StageShow` / `StageVisualTheme` / `RewardDefinition` / `GameplayRuleSet` 内存合同；
- 首次保存会在所选关卡目录生成计划约定的六文件包，`stage_definition.tres` 最后提交，并通过 lazy resource paths 组合其余资源；
- 已打开的关卡继续以 `SongChart` + `StageShow` 双文件事务保存；
- 写谱器会为所有新事件生成稳定 ID；
- 制谱 WAV 仅用于波形分析，正式预览仍读取 `SongDefinition.audio_stream`；
- 自动保存、波形缓存和备份写入 `user://minghe_chart_editor/`。
