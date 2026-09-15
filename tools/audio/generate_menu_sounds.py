"""从布料软接触实录制作菜单短音，依赖 NumPy；不在运行时合成。

原录音 lipalearning / soft impact.wav（CC0），截取范围见 sources/README.md。
"""
from pathlib import Path
import json
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/audio/menu/crafted"
RATE = 48000


def read_source(name):
    with wave.open(str(Path(__file__).parent / "sources" / f"{name}.wav"), "rb") as stream:
        assert (stream.getframerate(), stream.getsampwidth(), stream.getnchannels()) == (RATE, 2, 1)
        return np.frombuffer(stream.readframes(stream.getnframes()), "<i2") / 32768.0


def make_touch(source, start, duration, peak_db):
    count = round(duration * RATE)
    signal = source[round(start * RATE):round(start * RATE) + count].copy()
    # 保留布料原始纹理和低沉接触；仅去除直流及平滑切口，不增加乐音、变调或混响。
    signal -= signal.mean()
    edge = round(.003 * RATE)
    tail = round(min(.065, duration * .45) * RATE)
    signal[:edge] *= (.5 - .5 * np.cos(np.linspace(0, np.pi, edge)))
    signal[-tail:] *= (.5 + .5 * np.cos(np.linspace(0, np.pi, tail)))
    signal *= 10 ** (peak_db / 20) / np.max(np.abs(signal))
    return np.column_stack([signal, signal])


def write_wav(path, signal):
    with wave.open(str(path), "wb") as stream:
        stream.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        stream.writeframes(np.round(signal * 32767).astype("<i2").tobytes())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # 统一布料质感，确认稍实、返回稍低；高频操作缩短为很轻的接触反馈。
    specs = [
        ("focus", "fabric-tap", .001, .105, -33),
        ("confirm", "fabric-touch", .020, .190, -27),
        ("cancel", "fabric-low", .017, .180, -29),
        ("adjust", "fabric-tap", .001, .085, -35),
        ("open", "fabric-touch", .020, .230, -29),
    ]
    report, audition, rendered = [], [], {}
    for name, source, start, duration, peak in specs:
        signal = make_touch(read_source(source), start, duration, peak)
        write_wav(OUT / f"{name}.wav", signal)
        rendered[name] = signal
        report.append(dict(cue=name, duration_sec=duration, peak_db=peak,
                           rms_db=float(20 * np.log10(np.sqrt(np.mean(signal ** 2)))),
                           source="lipalearning / soft impact.wav / CC0"))
        audition.extend([signal, np.zeros((round(.65 * RATE), 2))])
        # 两种独立落点保留自然纹理；匹配原声能量并限制峰值，避免随机时忽大忽小。
        reference_rms = np.sqrt(np.mean(signal ** 2))
        for index, (take, offset) in enumerate([
                ("fabric-touch-2", .005), ("fabric-touch-3", .020)], start=2):
            variant = make_touch(read_source(take), offset, duration, peak)
            gain = reference_rms / np.sqrt(np.mean(variant ** 2))
            gain = min(gain, 10 ** ((peak + 2) / 20) / np.max(np.abs(variant)))
            variant *= gain
            key = f"{name}_{index}"
            write_wav(OUT / f"{key}.wav", variant)
            rendered[key] = variant
            report.append(dict(cue=key, duration_sec=duration,
                               peak_db=float(20 * np.log10(np.max(np.abs(variant)))),
                               rms_db=float(20 * np.log10(np.sqrt(np.mean(variant ** 2)))),
                               source="lipalearning / soft impact.wav / CC0"))
    review = ROOT / "builds/audio-review"
    review.mkdir(parents=True, exist_ok=True)
    write_wav(review / "menu-cues-fabric.wav", np.concatenate(audition))
    write_wav(review / "confirm-return-fabric.wav", np.concatenate([
        rendered["confirm"], np.zeros((round(.8 * RATE), 2)), rendered["cancel"]]))
    # 连续点击试听：打乱三种录音，禁止连续相同；每声后间隔 110 ms。
    rng = np.random.default_rng(20260915)
    sequence, previous = [], -1
    for _ in range(12):
        choice = int(rng.choice([i for i in range(3) if i != previous]))
        sequence.extend([rendered["confirm" if choice == 0 else f"confirm_{choice + 1}"],
                         np.zeros((round(.11 * RATE), 2))])
        previous = choice
    write_wav(review / "fabric-varied-clicks.wav", np.concatenate(sequence))
    (review / "levels.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
