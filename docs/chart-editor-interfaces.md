# 写谱器与游戏接入

产品依据：仓库外 `Docs/Program/《冥河，冥河！》写谱器设计说明书.md`。本文件只说明当前源码接线。

## 文件与领域对象

- `ChartJsonCodec`：JSON v1 与 `SongDefinition`／`SongChart` 双向转换，兼容未知内容存在 Resource 元数据中，不进入判定状态。
- `ChartProjectLoader.load_stage(song_json_or_zip, difficulty_id)`：游戏和工具的共同装配入口，返回 `stage` 与 `errors`。ZIP 音频直接从字节加载。
- `ChartProjectLoader.make_stage(song, chart)`：装配未保存的编辑版本，复用正式规则与主题。
- `StudioProjectIO`：项目文件、资源复制、工作区、迁移归档及 ZIP 管理。

新 JSON `format_version=1` 与 `SongChart.schema_version=2` 是不同版本体系。新增玩法需要同时补充编解码、工具表现和正式游戏语义；不能把未支持的字段静默解释成 Tap。

## 时间与预览

`StudioAudio` 是 EditorTransport 的实现，唯一拥有歌曲播放器、源音频位置、倍率、循环、试听补偿和暂停意图。其处理优先级为 -100，工作区随后消费本帧时间。编辑引起的预览重建不暂停音乐；恢复后无声追上当前时间，不补播历史反馈。内部 UI 使用音频秒坐标；预览公开定位入口使用音频整数微秒。

| 入口 | 用途 |
|---|---|
| `load_preview(stage, viewport)` | 加载正式 StageRoot，禁用自身歌曲播放与物理输入 |
| `update_preview(stage, viewport, audio_us)` | 更新编辑版本并恢复目标位置 |
| `seek_preview(audio_us)` | 重置正式模拟，无声重演到目标；后来的请求替换旧请求 |
| `set_transport(audio_us, playing)` | 同步当前播放位置和意图 |
| `get_preview_state()`、状态信号 | 返回重建状态、当前时间和权威快照 |

预览内部将音频位置减去首拍偏移，得到 StageSession 使用的本地歌曲时间；编译仍复用 `TempoMap` 的全谱 tick 偏移规则。示例定位使用 `seek_preview(4200000)`。

首拍继续保存为每难度 `timing.first_beat_offset_ms`，含义是有效 tick 0 的音频位置；谱面 tick 0 还需计入 `chart_offset_ticks`。没有额外波形偏移字段或格式升级。波形右拖 Δx 时首拍减少 Δx / pixels_per_second 秒，视口增加相同的首拍变化量以固定网格；拖标记和数值设置不移动视口。

共享 `StageSession.inject_preview_inputs` 接收同刻语义输入批次。每组先推进到不含端点，再处理固定顺序输入，再包含端点；输入来自正式理想输入生成器。无声重演保留所有领域事件，将表现快照汇总和时间动画刷新延后到目标。普通帧内也合并重复刷新。

修改判定器的部分仅为时间窗口索引、到达事件索引及校验扫描优化；判定窗口、Hold 断持规则、同刻处理和调频逻辑未改。回归中的既有失败见进度记录。

## 编辑历史

`StudioDocument` 分别保存歌曲字段历史与各难度的音符／谱面属性历史。`StudioTimeline` 保存选择、缩放、框选与手势候选，不把这些写入正式音符。一次拖画或拖动提交一次命令。

`set_first_beat_offset_ms(value, all_difficulties=false)` 只更新首拍字段，当前难度使用谱面历史；同步全部难度使用歌曲级历史，记录各受影响难度的新旧值，不替换音符对象。撤销和重做沿用这两个作用域。

时间线通过 `alignment_started`、`alignment_preview(seconds)`、`alignment_committed(seconds)`、`alignment_cancelled` 通知工作区。候选仅更新时间映射和绘制；工作区暂停音频，待提交后执行文档命令、刷新游标节拍基准及正式预览。取消恢复原映射与视口，音频保持暂停。波形右键通过 `waveform_context_requested(position, seconds)` 传递选点音频位置。

属性输入的提交集中排队，并在保存、切难度、开始时间线手势前处理；避免离焦后把旧输入写到新难度或新选区。普通数值输入不逐字重建属性面板。

## 启动与测试

`StudioLaunch` 识别 `minghe_chart_editor` feature、`--chart-editor` 参数和工具场景。写谱器模式隔离游戏设置与玩家存档启动。独立预设为 `Chart Studio Windows`。

测试入口是 `tests/editor/run.ps1`，包含协议／操作／恢复回归、Godot 键盘分发检查和工作区启动。`measure_audio.gd`、`measure_audio_longterm.gd`、`measure_performance.gd` 分别记录音频与密集谱面实测，不混入快速单元测试。

## 编钟提示与校准

`StudioCueEvents.build` 将正式 TempoMap、拍号、Tap／Hold 起手转换为内部秒事件。候选试听由 `StudioRhythmPanel.audition_changed` 通知，`audition_grid()` 只替换节拍器参照。事件不进入谱面 JSON。

`StudioCueTrack` 独占一条 AudioStreamGenerator；`StudioCueMixer` 是常驻线程唯一操作的数据对象，按输出采样率填充约 100 ms 队列。音乐仍经过独立 PitchShift 总线，提示保持原音高。音符声音从正式关卡的生／死钟素材独立解码，预览设置 `AudioFeedbackDirector.preview_strikes_muted` 防止重复起手；持续和判定声由“游戏反馈”开关控制。正式游戏该标志默认为 false，仍由实际有效输入请求声音。

定位、倍率、循环切换由 Transport 统一重建两路起点，音乐处理延迟只加在提示的样本位置上，共同设备输出延迟不重复加入。PCM 预填在音频锁外计算，锁内仅复位／注册播放；Generator 首块写入后重置内部重采样缓存。已提交队列保持不变，新编辑版本从未提交样本开始接管。欠载后重建两路基准并提示，避免持续错位。

producer 仅操作 RefCounted 数据和 Generator playback，不访问 Node；事件排序在状态锁外完成，短锁内替换候选版本并二分定位。每约 5 ms 检查缓冲，使用短 AudioServer 锁同步原生 RingBuffer，PCM 渲染不持驱动锁。启动事务之前须在驱动锁外 detach 旧 producer；关闭节点前 shutdown 并等待线程结束。负预滚段只提交零点以前的事件，零点起手只属于音乐播放段。

`CalibrationTapSession` 管理 4 拍准备和 24 次跟拍的本机输入补偿建议。校准窗口用固定样本参考音，中位早晚和离散程度来自实际回调取样；它不测纯设备输出延迟，输出／画面仍单独手调。结果经既有 SettingsService 保存，歌曲文件没有新增校准字段。
# 自动节奏分析接入

编辑器内部新增 `StudioRhythmJob`（任务及解码）、`StudioRhythmPanel`（候选 UI）、`StudioRhythmTools`（应用与草稿）。后台 JSON 接口包含 request_id、audio、model、start；结果包含 phase、beats、downbeats、fit、range、version、elapsed_seconds 或 error。时间以原歌曲秒数表达，选区起点由分析器补回。

候选标记和分析缓存不进入共同协议。对齐提交通过现有 `change_metadata`；草稿通过现有 `execute`。`ChartValidator.input_intervals` 与 `input_intervals_conflict` 暴露正式输入冲突查询，编辑器不复制判定窗口。详见 [节奏分析记录](chart-editor-rhythm-analysis.md)。
