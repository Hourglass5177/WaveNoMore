"""分析 Godot 总线录音的脉冲间隔；不把总线录音当作扬声器延迟测量。"""
import array
import json
import statistics
import sys
import wave
from pathlib import Path

directory = Path(sys.argv[1])
with wave.open(str(directory / "longterm.wav"), "rb") as recording:
    sample_rate = recording.getframerate()
    channels = recording.getnchannels()
    assert recording.getsampwidth() == 2, "录音需要 PCM16"
    pulses = []
    frame = 0
    while block := recording.readframes(sample_rate):
        samples = array.array("h", block)
        for index in range(0, len(samples), channels):
            if max(abs(value) for value in samples[index:index + channels]) > 1000:
                at = (frame + index // channels) / sample_rate
                if not pulses or at - pulses[-1] > 1:
                    pulses.append(at)
        frame += len(samples) // channels

trace_data = json.loads((directory / "longterm.json").read_text(encoding="utf-8"))
# 最后一秒音乐已结束，不用于累计漂移估计；以区间中位数减小进程调度抖动。
trace = [row for row in trace_data["trace"] if 2 < row["wall"] < 295]
early = statistics.median(row["transport"] - row["wall"] for row in trace[:20])
late = statistics.median(row["transport"] - row["wall"] for row in trace[-20:])
result = {
    "rate": trace_data["rate"],
    "sample_rate": sample_rate,
    "pulse_count": len(pulses),
    "pulse_span_seconds": pulses[-1] - pulses[0] if len(pulses) > 1 else None,
    "pulse_span_error_ms": ((pulses[-1] - pulses[0]) - 290) * 1000 if len(pulses) == 30 else None,
    "transport_vs_wall_drift_ms": (late - early) * 1000,
    "scope": "1x 五分钟，真实 WASAPI 总线录音；未包含扬声器、屏幕及其他倍率",
}
print(json.dumps(result, ensure_ascii=False, indent=2))
if len(sys.argv) > 2:
    Path(sys.argv[2]).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
