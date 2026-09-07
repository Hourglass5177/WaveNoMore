"""离线节奏识别子进程：只读 PCM 与本地模型，不接触谱面文件。"""
import argparse
import json
import os
from pathlib import Path
import time
import wave

VERSION = "beat-this-final0-v1"


def write(path, value):
    path = Path(path)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    os.replace(temp, path)


def fit_grid(beats, downbeats):
    """以间隔中位数编号，漏拍保留整数间隔；离群点不参与线性拟合。"""
    import numpy as np
    b = np.asarray(beats, dtype=float)
    if len(b) < 4:
        raise ValueError("可靠拍点不足，请选择节奏更明确的段落或手动对齐")
    period = float(np.median(np.diff(b)))
    indices = np.r_[0, np.cumsum(np.maximum(1, np.rint(np.diff(b) / period)))]
    mask = np.ones(len(b), dtype=bool)
    for _ in range(4):
        if mask.sum() < 4:
            break
        period, origin = np.polyfit(indices[mask], b[mask], 1)
        error = np.abs(b - (origin + indices * period))
        mask = error <= max(0.04, float(np.median(error)) * 3)
    db_indices = np.array([np.argmin(abs(b - d)) for d in downbeats], dtype=int)
    gaps = np.diff(indices[db_indices]) if len(db_indices) > 1 else np.array([])
    votes = {n: int(np.sum(gaps == n)) for n in (3, 4)}
    meter = max(votes, key=votes.get)
    if len(gaps) < 2 or votes[meter] / len(gaps) < 0.7:
        meter = 0
    anchor = float(origin + indices[db_indices[0]] * period) if len(db_indices) else float(origin)
    return {"bpm": float(60 / period), "anchor": anchor, "meter": meter,
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
                           "range": [start, start + len(signal) / sr],
                           "elapsed_seconds": time.perf_counter() - started})
    except Exception as error:
        write(args.result, {**state, "phase": "失败", "error": str(error)})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
