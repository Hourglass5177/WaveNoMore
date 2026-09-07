"""比较同一起点的 Godot 双总线脉冲录音；正偏差表示提示晚于音乐。"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import wave

import numpy as np


def pulse_onsets(path: Path, relative_threshold: float) -> dict:
    with wave.open(str(path), "rb") as audio:
        assert audio.getsampwidth() == 2, "测量要求 PCM16"
        rate = audio.getframerate()
        samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2")
        channels = audio.getnchannels()
        values = np.max(np.abs(samples.astype(np.float64).reshape(-1, channels)), axis=1)
    peak = float(values.max()) if values.size else 0.0
    if peak == 0:
        return {"sample_rate": rate, "frames": len(values), "peak": 0, "onsets": []}
    # 100ms 内的后处理振铃属于同一脉冲，不把阈值多次过零计作新音符。
    indices = np.flatnonzero(values > max(2.0, peak * relative_threshold))
    groups = np.split(indices, np.flatnonzero(np.diff(indices) > round(rate * 0.1)) + 1)
    return {"sample_rate": rate, "frames": len(values), "peak": peak,
            "onsets": [int(group[0]) / rate for group in groups if len(group)]}


def analyze(directory: Path) -> dict:
    manifest = json.loads((directory / "cue-sync.json").read_text(encoding="utf-8"))
    rows = []
    expected = len(manifest["expected_pulse_seconds"])
    for row in manifest["runs"]:
        item = dict(row)
        thresholds = {}
        for threshold in (0.01, 0.05, 0.1):
            music = pulse_onsets(directory / (row["id"] + "_music.wav"), threshold)
            cues = pulse_onsets(directory / (row["id"] + "_cues.wav"), threshold)
            complete = len(music["onsets"]) == expected == len(cues["onsets"])
            # 数量不完整时不按序强行配对，避免漏事件之后比较错误。
            differences = [(cue - note) * 1000 for note, cue in zip(music["onsets"], cues["onsets"])] if complete else []
            thresholds[str(threshold)] = {"music_count": len(music["onsets"]), "cue_count": len(cues["onsets"]),
                "music_peak": music["peak"], "cue_peak": cues["peak"], "music_frames": music["frames"], "cue_frames": cues["frames"],
                "music_onsets_sec": music["onsets"], "cue_onsets_sec": cues["onsets"], "cue_minus_music_ms": differences,
                "median_ms": float(np.median(differences)) if differences else None,
                "max_abs_ms": max(map(abs, differences)) if differences else None,
                "first_to_last_drift_ms": differences[-1] - differences[0] if differences else None,
                "first_to_last_drift_samples": round((differences[-1] - differences[0]) * cues["sample_rate"] / 1000) if differences else None}
        item["thresholds"] = thresholds
        main = thresholds["0.05"]
        item["pass_10ms"] = main["max_abs_ms"] is not None and main["max_abs_ms"] <= 10 and row["skipped_buffers"] == 0 and row["rendered_events"] == expected
        item["pass_5ms_drift"] = main["first_to_last_drift_ms"] is not None and abs(main["first_to_last_drift_ms"]) <= 5
        item["pass_single_start"] = row.get("stream_starts") == 1
        rows.append(item)
    return {key: value for key, value in manifest.items() if key != "runs"} | {
        "method": "相同混音块开始/结束的 PCM16 总线录音，主起音阈值为各通道峰值的5%，另列1%和10%敏感性；不据此推断真人输入或蓝牙延迟。",
        "passed": sum(row["pass_10ms"] for row in rows),
        "single_start_passed": sum(row["pass_single_start"] for row in rows), "total": len(rows), "runs": rows}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--sets", nargs="*", help="汇总指定子目录，例如 pulse life death long")
    parser.add_argument("--summary", type=Path, help="输出可纳入版本管理的测量摘录")
    args = parser.parse_args()
    directories = [args.directory / name for name in args.sets] if args.sets else [args.directory]
    summaries = []
    for directory in directories:
        result = analyze(directory)
        (directory / "cue-sync-analysis.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        rows = []
        for row in result["runs"]:
            stats = row["thresholds"]["0.05"]
            print(directory.name, row["id"], "median_ms=", stats["median_ms"], "max_abs_ms=", stats["max_abs_ms"],
                  "events=", stats["music_count"], stats["cue_count"], "skips=", row["skipped_buffers"], "pass=", row["pass_10ms"])
            rows.append({key: value for key, value in row.items() if key != "thresholds"} | {
                "onset_5pct": {key: value for key, value in stats.items() if not isinstance(value, list)},
                "threshold_sensitivity_max_abs_ms": {key: values["max_abs_ms"] for key, values in row["thresholds"].items()}})
        summaries.append({key: value for key, value in result.items() if key != "runs"} | {"raw_directory": directory.as_posix(), "runs": rows})
        print("CUE SYNC", result["passed"], "/", result["total"])
    if args.summary:
        summary = {"analyzed_utc": datetime.now(timezone.utc).isoformat(),
            "limits": "这是独立最小化探针中合成脉冲/现有灰盒编钟素材的混音总线测量，使用正常音频驱动。未覆盖物理输出、真人输入、蓝牙、完整工作区的10000音符压力或所有定位/循环情形。实际输出采样率见各项，不将源采样率冒充输出采样率；5分钟长测仅覆盖48kHz源与输出、1倍、30FPS。",
            "groups": summaries}
        args.summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
