#!/usr/bin/env bash
#
# 把 preview/<slug>/<slug>_*.png 安装到 ~/Library/Application Support/DeskPet/characters/<slug>/
# 同时把文件名的角色前缀去掉(example_idle.png → idle.png)
#
# 用法:
#   ./tools/install_character.sh example
#   ./tools/install_character.sh example

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREVIEW_DIR="$PROJECT_DIR/preview"
APP_SUPPORT="$HOME/Library/Application Support/DeskPet/characters"

if [[ -z "$1" ]]; then
    echo "用法: $0 <character-slug>"
    echo ""
    echo "preview/ 里现有:"
    ls "$PREVIEW_DIR" 2>/dev/null | sed 's/^/  - /'
    exit 1
fi

SLUG="$1"
SRC="$PREVIEW_DIR/$SLUG"
DST="$APP_SUPPORT/$SLUG"

if [[ ! -d "$SRC" ]]; then
    echo "✗ 找不到 $SRC"
    exit 1
fi

mkdir -p "$DST"

echo "→ 安装 $SLUG 到 $DST"
count=0
for src_file in "$SRC"/${SLUG}_*.png; do
    [[ -f "$src_file" ]] || continue
    base_name=$(basename "$src_file" | sed "s/^${SLUG}_//")
    cp "$src_file" "$DST/$base_name"
    echo "    $base_name"
    count=$((count + 1))
done

if [[ "$count" -eq 0 ]]; then
    echo "✗ $SRC 里没找到 ${SLUG}_*.png"
    rm -rf "$DST"
    exit 1
fi

echo ""
echo "✓ 安装了 $count 个文件"
echo "  现在在 DeskPet 状态栏菜单 → 切换角色,应该能看到「$(echo $SLUG)」"

# 复制 profile 作为运行时 meta(供 CharacterRegistry 读 done_sound、display_name 等)
PROFILE_SRC="$PROJECT_DIR/tools/profiles/$SLUG.json"
if [[ -f "$PROFILE_SRC" ]]; then
    cp "$PROFILE_SRC" "$DST/meta.json"
    echo "    meta.json"
fi

echo "  (如果是新装,可能要重启 swift run 才能扫到)"
