# 古楚拟音 AudioLab

九条固定 IPA 材料的本地试验。优先核对音素实现与重复稳定性，音色暂用默认值。游戏工程无需安装这些依赖。

打开 `index.html` 试听；每条音频旁的参数链接可查看原始 IPA、引擎输入、模型条件和技术检查。运行后用 `run.ps1 preview` 更新页面。

## 已准备的材料

`samples.json` 保存视频字幕来源、今读、IPA 和检查重点。各样例三次生成，共 27 段／后端。小样是“玉、以、兮、溘”各一次；后续全量命令补齐剩余文件，不重复生成已有结果。

声音是项目选定拟音的合成候选，并非专家审定的战国楚语示范。`cmn` 是模型合成条件，不能理解为模型具备“楚语”选项。

## 运行

在项目根目录用 PowerShell 执行：

```powershell
./AudioLab/run.ps1 prepare
./AudioLab/run.ps1 audit
./AudioLab/run.ps1 toucan-smoke
./AudioLab/run.ps1 toucan
./AudioLab/run.ps1 check
./AudioLab/run.ps1 preview
```

`runtime/bootstrap` 是 Eleven 和页面工具的环境；`runtime/toucan` 为独立 Python 3.10 和 CUDA PyTorch 环境。目录迁移到另一绝对路径时，应重建虚拟环境。

当前依赖已安装；如重建 Toucan 环境，先安装 `torch==2.4.1`、`torchaudio==2.4.1`（PyTorch 官方 cu121 索引），再安装 `requirements-toucan.txt`。完整实测版本见 `requirements-toucan-lock.txt`。本试验的直接 IPA 路径不需要安装 eSpeak NG 或文字转音素模型。

## Eleven 账号就绪后

在 ElevenLabs 建立账号与 API 密钥，并在**自己的本地 PowerShell**中设置 `ELEVENLABS_API_KEY`。不要把密钥发到聊天或保存进输入表。为避免直接将密钥写入命令历史，可以采用：

```powershell
$chuSecret = Read-Host 'ElevenLabs API key' -AsSecureString
$env:ELEVENLABS_API_KEY = [System.Net.NetworkCredential]::new('', $chuSecret).Password
./AudioLab/run.ps1 eleven-smoke
```

听过四条小样后执行：

```powershell
./AudioLab/run.ps1 eleven
./AudioLab/run.ps1 check
```

脚本固定 `eleven_v3`、预置声 `21m00Tcm4TlvDq8ikWAM`，使用服务默认音色参数和无情绪的 IPA 文本。请求失败或额度不足立即停止，保留已经保存的文件；不会自动购买额度或创建声音。网络中断时不自动重发可能已计费的请求。无密钥时只生成待试材料，不发送请求。

## 文件用途

- `outputs/eleven`、`outputs/toucan`：分段音频、对应参数和后端状态。
- `outputs/toucan/input_audit.json`：每条输入的音素、附加符号关联和特征核对。
- `outputs/technical_check.json`：文件解码、非静音、削波和试听链接检查。
- `vendor`：固定版本官方源码及原始压缩包；本地适配说明见 `VENDOR_NOTES.md`。
- `models`、`cache`、`runtime`：下载权重、缓存与依赖，不属于游戏资源。

输入改变时，使用新样例 ID，以免与既有结果混淆。脚本默认保留已有 take，不提供自动覆盖录音的选项。

## 如何听审

先听是否增添元音、漏字、丢掉韵尾，再检查清浊、送气、咽化等细节。三次生成不同是观察结果，不自动判为错误。同一个词的声学特征是否准确，需由具备相应听辨能力的人确认；普通话 ASR 不能替代这一过程。

本次不加载参考音色编码器和文字转音素模型，使用官方声学模型自带的默认说话人向量。`~`、`#` 是推理静音／句末标记，不是应读出的古楚音素。源码的最小调整及模型版本见 `VENDOR_NOTES.md`。
