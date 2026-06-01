# Tools - 角色多帧生成 pipeline

## 一次性配置

```bash
# 1. 装依赖(已经装过的话跳过)
pip3 install google-genai pillow rembg onnxruntime

# 2. 拿 Gemini API key
# https://aistudio.google.com/apikey  (免费,2 分钟)

# 3. 设环境变量(加到 ~/.zshrc 永久生效)
export GEMINI_API_KEY=你的key
```

## 跑批量生成

```bash
cd ~/Desktop/deskpet
python3 tools/character_frames.py
```

预期输出:7 张新 sprite,落到 `Sources/DeskPet/Resources/`:
- `example_walk_a.png`, `example_walk_b.png`
- `example_thinking_a.png`, `_b.png`, `_c.png`
- `example_done_a.png`, `_b.png`

每张 ~5-10 秒(生成 + rembg 后处理),全部 ~1-2 分钟跑完。

## 单张生成 / 重生

某张不满意,先删,再跑:

```bash
rm Sources/DeskPet/Resources/example_walk_a.png
python3 tools/character_frames.py   # 只补缺失那张
```

或者用单文件接口直接出图到任意位置:

```bash
python3 tools/generate.py "prompt 文本" \
  --ref Sources/DeskPet/Resources/example_idle.png \
  --out /tmp/test.png
```

## 给新角色生成

把 `character_frames.py` 里的 `CHARACTER` 常量换成新角色名(比如 `Agatsuma Zenitsu`),
顺手把 BASE_PROMPT 里的"hair / cape / 武器"特征换掉,删掉旧的 PNG,跑一次就好。

## 扣图模型 / 浅发角色(踩过坑)

默认扣图模型是 `isnet-anime`,但它会把**浅色/低饱和的细尖发当背景吃掉**
(Rick 浅蓝尖发扣完变秃头)。这类角色在 `tools/profiles/<slug>.json` 里加一行
`"strip_model": "birefnet-general"`,pipeline 会自动用对的模型。
手动重扣单张:`python3 tools/strip_bg.py --model birefnet-general file.png`。

## mini-mode 贴边帧(peek)

`./tools/regen_peek.sh <slug>` 只重生贴边探头帧:Gemini 出 `peek_right`,
再水平镜像成 `peek_left`(引擎在 mini mode 不翻转 sprite,两张都要预烘)。
外貌从 profile 的 `quick_visual` 读,扣图模型从 `strip_model` 读。非内置角色会自动同步进已安装目录。

## 成本

Gemini 2.5 Flash Image:
- 免费层:1500 张/天(完全够)
- 付费层:~$0.04/张,一个角色 7 帧 ≈ $0.30
