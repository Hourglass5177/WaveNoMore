"""离线节奏识别子进程：只读 PCM 与本地模型，不接触谱面文件。"""
import argparse
import json
import os
from pathlib import Path
import time
import wave

VERSION = "beat-this-final0-v1"
FIT_VERSION = "local-grid-v3"


def write(path, value):
    path = Path(path)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    os.replace(temp, path)


def fit_grid(beats, downbeats, fit_range=None):
    """只汇总局部斜率；跨段漏拍、半速和相位跳变不会拉动全曲回归线。"""
    import numpy as np
    b = np.unique(np.asarray(beats, dtype=float))
    b = b[np.isfinite(b)]
    d = np.asarray(downbeats, dtype=float)
    if fit_range is not None:
        b = b[(b >= fit_range[0]) & (b <= fit_range[1])]
        d = d[(d >= fit_range[0]) & (d <= fit_range[1])]
    if len(b) < 4:
        raise ValueError("可靠拍点不足，请选择节奏更明确的段落或手动对齐")
    windows = []
    starts = list(range(0, max(1, len(b) - 15), 8))
    if len(b) >= 16 and starts[-1] != len(b) - 16:
        starts.append(len(b) - 16)
    for start in starts:
        local = b[start:start + 16]
        initial = float(np.median(np.diff(local)))
        indices = np.r_[0, np.cumsum(np.maximum(1, np.rint(np.diff(local) / initial)))]
        mask = np.ones(len(local), dtype=bool)
        period, origin = initial, local[0]
        for _ in range(4):
            if mask.sum() < 4:
                break
            period, origin = np.polyfit(indices[mask], local[mask], 1)
            error = np.abs(local - (origin + indices * period))
            mask = error <= max(0.025, float(np.median(error)) * 3)
        p95 = float(np.percentile(np.abs(local - origin - indices * period), 95))
        windows.append({"start": float(local[0]), "end": float(local[-1]),
                        "period": float(period), "p95_ms": p95 * 1000,
                        "stable": bool(len(local) >= 8 and p95 <= 0.04 and period > 0)})
    usable = [w for w in windows if w["stable"]]
    # 过短或不稳定的检测仍可供人工修正，但不能把它称为可靠的小节定位。
    candidates = usable or windows
    # 归一化的参照必须来自真实窗口；两个不相容速度各占一半时，
    # 它们的算术中位数可能并不对应歌曲中的任何速度。
    central = float(np.median([w["period"] for w in candidates]))
    base = min(candidates, key=lambda w: abs(w["period"] - central))["period"]
    for window in windows:
        octave = round(float(np.log2(window["period"] / base)))
        window["normalized_period"] = window["period"] / 2 ** octave
        window["beat_scale"] = 2 ** octave
    # 先找具有最多局部支持的周期簇，再在簇内汇总；相同支持时选最早
    # 的稳定段落。避免真正变速的两段被平均成不存在的全曲 BPM。
    def supporters(reference):
        return [w for w in candidates
                if abs(w["normalized_period"] / reference["normalized_period"] - 1) <= 0.02]

    representative = max(candidates, key=lambda w: len(supporters(w)))
    consistent = supporters(representative)
    period = float(np.median([w["normalized_period"] for w in consistent]))
    for window in windows:
        window["stable"] = bool(window["stable"] and abs(window["normalized_period"] / period - 1) <= 0.02)
    anchor, anchor_confirmed = float(b[0]), False
    reference_range = [float(b[0]), float(b[-1])]
    for window in windows:
        if not window["stable"]:
            continue
        refs = d[(d >= window["start"] - 0.04) & (d <= window["end"] + 0.04)]
        refs = [float(t) for t in refs if np.min(abs(b - t)) <= 0.04]
        if len(refs) >= 2:
            anchor, anchor_confirmed = refs[0], True
            reference_range = [window["start"], window["end"]]
            break
    # 拍号只采用落在候选周期上的重拍间隔；缺少一致证据时由谱师确认。
    gaps = np.diff(d) / period
    votes = {n: int(np.sum(abs(gaps - n) <= 0.15)) for n in (3, 4)}
    meter = max(votes, key=votes.get)
    if len(gaps) < 2 or votes[meter] / len(gaps) < 0.7:
        meter = 0
    error = np.abs(b - (anchor + np.rint((b - anchor) / period) * period))
    return {"bpm": float(60 / period), "anchor": anchor, "meter": meter,
            "version": FIT_VERSION, "anchor_confirmed": anchor_confirmed,
            "reference_range": reference_range, "windows": windows,
            "half_time_detected": any(w["stable"] and w["beat_scale"] != 1 for w in windows),
            "median_error_ms": float(np.median(error) * 1000),
            "p95_error_ms": float(np.percentile(error, 95) * 1000)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--result", required=True)
    args = parser.parse_args()
    request = json.loads(Path(args.request).read_text(encoding="utf-8-sig"))
    started = time.perf_counter()
    state = {"request_id": request["request_id"], "version": VERSION}
    try:
        # 旧缓存和选区修正只重算轻量拟合，不加载 torch 或模型。
        if "raw" in request:
            raw = request["raw"]
            write(args.result, {**state, "phase": "拟合节奏"})
            fit = fit_grid(raw["beats"], raw["downbeats"], request.get("fit_range"))
            write(args.result, {**raw, **state, "phase": "完成", "fit": fit,
                               "fit_version": FIT_VERSION, "fit_range": request.get("fit_range"),
                               "refit_seconds": time.perf_counter() - started})
            return 0
        write(args.result, {**state, "phase": "加载模型"})
        import numpy as np
        import torch
        from beat_this.inference import Audio2Beats
        torch.set_num_threads(min(4, max(1, (os.cpu_count() or 2) // 2)))
        model = Path(request["model"])
        if not model.is_file():
            raise ValueError("本地节奏模型缺失，请重新解压完整开发包")
        processor = Audio2Beats(checkpoint_path=str(model), device="cpu", float16=False, dbn=False)
        with wave.open(request["audio"], "rb") as audio:
            sr = audio.getframerate()
            if audio.getnchannels() != 1 or audio.getsampwidth() != 2:
                raise ValueError("分析音频需要单声道 PCM16")
            signal = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2").astype(np.float32) / 32768
        write(args.result, {**state, "phase": "识别拍点"})
        beats, downbeats = processor(signal, sr)
        start = float(request.get("start", 0))
        beats = beats + start
        downbeats = downbeats + start
        write(args.result, {**state, "phase": "拟合节奏"})
        fit = fit_grid(beats, downbeats)
        write(args.result, {**state, "phase": "完成", "beats": beats.tolist(),
                           "downbeats": downbeats.tolist(), "fit": fit,
                           "fit_version": FIT_VERSION,
                           "range": [start, start + len(signal) / sr],
                           "elapsed_seconds": time.perf_counter() - started})
    except Exception as error:
        write(args.result, {**state, "phase": "失败", "error": str(error)})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
