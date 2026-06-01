# 桌宠角色生成 Prompt 模板

通用结构 = 通用基础 prompt + 4 个状态描述,只换角色名和 `[signature_*]` 占位符。

## 通用基础 prompt(每次都加)

```
Chibi Q-version full body portrait of [character name].

Style:
- Clean anime cel-shading, smooth consistent line work
- Head-to-body ratio approximately 1:2 (true chibi proportions)
- Character facing camera directly, no perspective tilt
- Full body in frame, centered composition

Background (CRITICAL):
- TRUE transparent background, PNG alpha channel = 0
- DO NOT draw checkerboard pattern
- DO NOT use white background
- NO scenery, NO environment elements
- Character completely isolated, every non-character pixel must be transparent

Quality:
- High resolution
- No text, no watermark, no signature
- Only the character, no decorations or borders

Pose and expression: [此处插入状态描述]
```

## 状态描述

### 1. Idle(默认呼吸)
```
Standing relaxed, arms at sides, eyes open looking forward,
gentle confident smile.
```

### 2. Blink(眨眼帧 - 关键:与 idle 同姿态)
```
EXACT SAME pose as the idle reference image,
ONLY difference: eyes closed peacefully.
```

### 3. Walk A(走路低点 - 左脚向前)
```
Walking sprite, facing RIGHT (3/4 side view), eyes open.
DOWN phase of walk cycle.

LEGS - wide stride:
- LEFT foot stepped FAR FORWARD, planted flat on ground
- RIGHT foot trailing BEHIND, heel lifted
- At least one body-width between feet
- Body leaning slightly forward over the planted left leg

ARMS counter-swing: RIGHT arm forward, LEFT arm back.

MOTION FX:
Small white/gray dust puff just behind the RIGHT foot
(the foot that just left the ground), plus a few small speed lines.
```

### 4. Walk Mid(走路高点 - 过渡帧)
```
UP phase of walk cycle - passing pose, facing RIGHT (3/4 view).

- Both feet close together at the same horizontal position
- Body clearly lifted up, highest point of walking bounce
- Both arms in neutral position at sides
- Knees slightly bent
```

### 5. Walk B(走路低点 - 右脚向前)
```
Walking sprite, facing RIGHT (3/4 side view), eyes open.
DOWN phase, MIRROR / OPPOSITE of Walk A.

LEGS - wide stride, opposite of Walk A:
- RIGHT foot stepped FAR FORWARD, planted flat on ground
- LEFT foot trailing BEHIND, heel lifted
- At least one body-width between feet
- Body leaning slightly forward over the planted right leg

ARMS counter-swing, opposite of Walk A: LEFT arm forward, RIGHT arm back.

MOTION FX:
Small white/gray dust puff just behind the LEFT foot
(opposite side from Walk A), plus a few small speed lines.

CRITICAL:
Walk A dust is behind RIGHT foot; Walk B dust must be behind LEFT foot.
The alternating dust and opposite lead foot are the key visual signals of stepping.
```

### 6. Done(完成任务,庆祝)
```
One hand giving thumbs up, big open-mouth smile,
eyes squinted happily, confident energetic posture,
surrounded by [signature_celebration] for celebration.
```

### 6.5 Peek(mini mode 贴边扒墙探头)
```
Mini-mode 贴边时显示。引擎把窗口滑出屏幕,只留靠内侧 ~100px 可见,
所以角色要画成"扒在屏幕边缘探头"的半隐藏姿态,不是正常站立。

只画 peek_right(贴右边缘);peek_left 由 peek_right 水平镜像自动生成
(引擎在 mini mode 不翻转 sprite,所以两张都要预烘成文件)。

构图(peek_right):
- 角色 CLING 在画面右侧的竖直边缘上,头朝 LEFT 探出(往屏幕里看)
- 头、脸、近侧肩膀、抓握的手 都在画面 LEFT 部分,完整可见
- 下半身/腿往画面 RIGHT 侧弯出(App 会裁掉这部分)
- 至少一只手明显 GRIP 住右侧竖直边缘,手指扣在边沿上(像扒着墙角)
- 眼睛看 LEFT,好奇/俏皮探头表情,signature 特征和服装与 idle 一致
- 不画真实的墙/边缘物体,靠抓握手势暗示,其余全透明
```

单张手动重生(配合 tools/generate.py,以 idle 作 reference):
```
EDIT THE REFERENCE IMAGE. Keep face, head shape, [signature features by name],
body proportions and color palette IDENTICAL. ONLY change the pose to the edge-cling below.

Mini-mode peek pose — clinging around the RIGHT edge:
- The chibi character CLINGS to a vertical edge to the character's RIGHT, peeking out toward the LEFT.
- Place the character in the LEFT portion of the frame: HEAD, face, near shoulder and the GRIPPING HAND(S)
  fully visible on the screen-LEFT; lower body / legs curve away toward the RIGHT side of the frame.
- At least one hand visibly GRIPS the vertical edge, fingers curled over an implied ledge, pulling the body around the corner.
- Head and eyes turned LEFT, curious playful peeking expression, gentle confident smile.
- HALF-HIDDEN peek-around-the-corner cling, NOT an upright standing pose.

Background: TRUE transparent PNG (alpha=0). DO NOT draw a wall, ledge, shelf, scenery, checkerboard or white bg
— the grip pose alone implies the edge; everything outside the character is transparent.
Body FULLY OPAQUE with a CLEAR SHARP SILHOUETTE. No text, no watermark, no signature, no border.
```
之后 peek_left 用 `peek_right` 水平翻转即可(character_frames.py 已自动做)。

### 7. Thinking / 积蓄力量
```
[战斗向角色]
Battle ready stance, slightly crouched, intense determined gaze,
[signature_pose, e.g. gripping katana / clenched fist / forming seals],
[signature_power] gathering around the body
(keep effect moderate, character must remain clearly visible).

[非战斗向角色]
Concentrated thinking expression, slightly furrowed brow / hand on chin / arms crossed,
small thought bubbles or question marks around head.
```

## signature 字段怎么填(按原型举例,自己的角色照着想)

这几个字段决定 thinking/done 帧的特效。按角色"原型"填即可,下面是通用示例:

| 原型 archetype | signature_celebration | signature_power | signature_pose |
|---|---|---|---|
| Fire / flame type | small flame sparks | flames swirling and gathering | battle stance, weapon raised |
| Lightning type | small lightning sparks | lightning arcs gathering | crouched, one foot raised |
| Water type | water droplets and sparkles | water ripples and waves circling | calm focused stance |
| Energy / aura type | glowing particles | colored energy aura swirling | one hand raised |
| Robot / mech type | gear sparkles, confetti | neon circuit glow pulsing | arms crossed, LED eyes |
| Cute / non-combat | sparkles, confetti | (用非战斗向描述,见上文 #7) | hand on chin, thinking |

## 操作流程(关键)

1. 用 base + idle 描述生成 idle → 多张里挑最满意的
2. 把那张 idle 作为 **reference image** 喂给后续生成
   - Midjourney: `--cref [URL] --cw 100`
   - nano banana / GPT-4o: 直接拖参考图进对话
3. 用 base + 其他状态描述 + reference image 生成 blink / done / thinking
4. 这样 4 张的发型、身高、衣服细节、signature 风格才能一致

## 后处理

nano banana 经常画棋盘格代替真透明背景。每次生成后用 `tools/strip_bg.py` 扣一遍(pipeline 已自动调):

```bash
python3 tools/strip_bg.py file.png                          # 默认 isnet-anime
python3 tools/strip_bg.py --model birefnet-general file.png # 浅发角色
```

**扣图模型选择(重要)**:
- `isnet-anime`(默认):深色/高饱和动漫角色最佳(深色饱和发色的角色)。
- `birefnet-general`:**浅色/低饱和头发的角色必须用这个**。isnet-anime 会把浅蓝/浅灰细尖发当背景吃掉(Rick 浅蓝尖发踩过坑,扣完变秃头)。
- `u2net` / `isnet-general-use`:一般更差(易留白墙、把发变白),别用。

角色专属:在 `tools/profiles/<slug>.json` 写 `"strip_model": "birefnet-general"`,
`character_frames.py` 和 `regen_peek.sh` 会自动读取并传给 strip。Rick 已标注。
