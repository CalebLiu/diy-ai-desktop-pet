#!/usr/bin/env bash
#
# 只重生 mini-mode 贴边帧:peek_right(Gemini 生成)+ peek_left(水平镜像)
# 外貌特征从 tools/profiles/<slug>.json 的 quick_visual 读取,对任何角色通用。
#
# 用法:
#   export GEMINI_API_KEY=...
#   ./tools/regen_peek.sh <slug>     # 写进 preview/<slug>/ 并同步到已安装目录
#
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SLUG="${1:?用法: ./tools/regen_peek.sh <slug>}"
PROFILE="$ROOT/tools/profiles/$SLUG.json"

if [[ -z "$GEMINI_API_KEY" ]]; then
    echo "✗ 先 export GEMINI_API_KEY=...  (https://aistudio.google.com/apikey)"
    exit 1
fi
if [[ ! -f "$PROFILE" ]]; then
    echo "✗ 找不到 profile: $PROFILE"
    exit 1
fi

# 从 profile 读 quick_visual(逗号分隔的签名特征),喂进 "Keep ... IDENTICAL"
QUICK_VISUAL=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['quick_visual'])" "$PROFILE")
# 浅发角色在 profile 里写 "strip_model": "birefnet-general";默认 isnet-anime
STRIP_MODEL=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('strip_model',''))" "$PROFILE")

RES="$ROOT/preview/$SLUG"
PREFIX="${SLUG}_"
mkdir -p "$RES"
IDLE="$RES/${PREFIX}idle.png"
OUT_RIGHT="$RES/${PREFIX}peek_right.png"
OUT_LEFT="$RES/${PREFIX}peek_left.png"

if [[ ! -f "$IDLE" ]]; then
    echo "✗ 找不到 idle 参考图: $IDLE"
    exit 1
fi

PROMPT="EDIT THE REFERENCE IMAGE. Keep face, head shape, ${QUICK_VISUAL}, body proportions and color palette IDENTICAL. ONLY change the pose to the edge-cling below.

Mini-mode peek pose — clinging around the RIGHT edge:
- The chibi character CLINGS to a vertical edge to the character's RIGHT, peeking out toward the LEFT (into the screen).
- Place the character in the LEFT portion of the frame: HEAD, face, near shoulder and the GRIPPING HAND(S) fully visible on the screen-LEFT; lower body and legs curve away toward the RIGHT side of the frame.
- At least one hand visibly GRIPS the vertical edge, fingers curled over an implied ledge, pulling the body around the corner.
- Head and eyes turned LEFT, curious playful peeking expression.
- HALF-HIDDEN peek-around-the-corner cling, NOT an upright standing pose.

Background (CRITICAL): TRUE transparent PNG, alpha = 0. DO NOT draw a wall, ledge, shelf, scenery, checkerboard pattern or white background — the grip pose alone implies the edge; every pixel outside the character is transparent.
The character body must be FULLY OPAQUE with a CLEAR SHARP SILHOUETTE.
No text, no watermark, no signature, no border."

echo "→ [$SLUG] 生成 peek_right (ref: $(basename "$IDLE"))"
echo "  签名特征: $QUICK_VISUAL"
python3 "$ROOT/tools/generate.py" "$PROMPT" --ref "$IDLE" --out "$OUT_RIGHT"
if [[ -n "$STRIP_MODEL" ]]; then
    python3 "$ROOT/tools/strip_bg.py" --model "$STRIP_MODEL" "$OUT_RIGHT"
else
    python3 "$ROOT/tools/strip_bg.py" "$OUT_RIGHT"
fi

echo "→ 镜像生成 peek_left ..."
python3 - "$OUT_RIGHT" "$OUT_LEFT" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1]).transpose(Image.FLIP_LEFT_RIGHT).save(sys.argv[2])
PY

# 若该角色已安装,把两帧同步进 app-support 目录(文件名去前缀)
INSTALLED="$HOME/Library/Application Support/DeskPet/characters/$SLUG"
if [[ -d "$INSTALLED" ]]; then
    cp "$OUT_RIGHT" "$INSTALLED/peek_right.png"
    cp "$OUT_LEFT"  "$INSTALLED/peek_left.png"
    echo "  ✓ 已同步到 $INSTALLED/{peek_right,peek_left}.png"
fi

echo ""
echo "✓ 完成:"
echo "    $OUT_RIGHT"
echo "    $OUT_LEFT"
echo "  切到「$SLUG」角色,拖到屏幕边缘进 mini mode 验证"
