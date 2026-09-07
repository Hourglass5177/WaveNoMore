# 本地节奏识别器第三方说明

识别器在本机 CPU 上运行，使用 FP32；不使用 CUDA、DBN 或在线服务。运行时只读取随包的模型，不下载模型。不要单独移动主 EXE；保留同目录的 `rhythm_analyzer` 文件夹。

- Beat This! 1.1.0，代码与公开模型为 MIT 许可：https://github.com/CPJKU/beat_this
- 模型：官方 `final0`，来源 https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp/final0.ckpt
- 预处理、分块推理及后处理复用官方 `Audio2Beats`，参数 `device=cpu, float16=False, dbn=False`。
- PyTorch、TorchAudio、NumPy、soxr、einops、rotary-embedding-torch、Python 和 PyInstaller 等依赖的许可证随本目录附带。精确版本见 `requirements-lock.txt`。
- PyInstaller 使用 GPL 许可证及其允许分发生成程序的特殊例外；具体以附带原文为准：https://pyinstaller.org/en/stable/license.html

识别结果为辅助候选，不代表人工确认的节奏或小节位置。模型输出的时间分辨率、半速／倍速歧义及音乐本身会影响结果。
